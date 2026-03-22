import type { AcceptInvitationResponse, CreateInvitationRequest, CreateInvitationResponse, GetInvitationByTokenResponse } from "@dcapx/contracts";
import { prisma } from "../../db";
import { ApiError } from "../../lib/errors/api-error";
import { generateInvitationToken, hashInvitationToken } from "./invitation-token";

class InvitationsService {
  async createInvitation(invitedByUserId: string, request: CreateInvitationRequest): Promise<CreateInvitationResponse> {
    const rawToken = generateInvitationToken();
    const tokenHash = hashInvitationToken(rawToken);
    const expiresAt = new Date(Date.now() + (request.expiresInHours ?? 72) * 60 * 60 * 1000);
    const invitation = await prisma.invitation.create({
      data: {
        tokenHash,
        email: request.email.toLowerCase(),
        invitationType: request.invitationType,
        targetRoleCode: request.targetRoleCode,
        invitedByUserId,
        partnerOrganizationId: request.partnerOrganizationId ?? null,
        advisorUserId: request.advisorUserId ?? null,
        expiresAt,
      },
    });
    return {
      invitationId: invitation.id,
      status: invitation.status as any,
      expiresAtUtc: invitation.expiresAt.toISOString(),
      inviteUrl: `${process.env.WEB_APP_URL}/invite/${rawToken}`,
    };
  }
  async getInvitationByToken(rawToken: string): Promise<GetInvitationByTokenResponse> {
    const tokenHash = hashInvitationToken(rawToken);
    const invitation = await prisma.invitation.findUnique({ where: { tokenHash } });
    if (!invitation) {
      throw new ApiError({ statusCode: 404, code: "INVITATION_NOT_FOUND", message: "Invitation not found." });
    }
    if (invitation.expiresAt.getTime() < Date.now() && invitation.status === "PENDING") {
      await prisma.invitation.update({ where: { id: invitation.id }, data: { status: "EXPIRED" } });
      throw new ApiError({ statusCode: 410, code: "INVITATION_EXPIRED", message: "Invitation has expired." });
    }
    return {
      invitationId: invitation.id,
      email: invitation.email,
      invitationType: invitation.invitationType as any,
      targetRoleCode: invitation.targetRoleCode,
      partnerOrganizationId: invitation.partnerOrganizationId,
      advisorUserId: invitation.advisorUserId,
      status: invitation.status as any,
      expiresAtUtc: invitation.expiresAt.toISOString(),
    };
  }
  async acceptInvitation(rawToken: string, acceptedUserId: string): Promise<AcceptInvitationResponse> {
    const tokenHash = hashInvitationToken(rawToken);
    const invitation = await prisma.invitation.findUnique({ where: { tokenHash } });
    if (!invitation || invitation.status !== "PENDING") {
      throw new ApiError({ statusCode: 400, code: "INVITATION_NOT_ACCEPTABLE", message: "Invitation cannot be accepted." });
    }
    const updated = await prisma.invitation.update({
      where: { id: invitation.id },
      data: { status: "ACCEPTED", acceptedAt: new Date(), acceptedUserId },
    });
    if (updated.advisorUserId && updated.targetRoleCode === "CLIENT") {
      await prisma.advisorClientAssignment.create({
        data: { advisorUserId: updated.advisorUserId, clientUserId: acceptedUserId, status: "ACTIVE" },
      });
    }
    return {
      invitationId: updated.id,
      status: "ACCEPTED",
      acceptedAtUtc: updated.acceptedAt!.toISOString(),
    };
  }
}
export const invitationsService = new InvitationsService();
