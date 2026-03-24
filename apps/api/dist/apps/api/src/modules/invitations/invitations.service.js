"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.invitationsService = void 0;
const db_1 = require("../../db");
const api_error_1 = require("../../lib/errors/api-error");
const invitation_token_1 = require("./invitation-token");
class InvitationsService {
    async createInvitation(invitedByUserId, request) {
        const rawToken = (0, invitation_token_1.generateInvitationToken)();
        const tokenHash = (0, invitation_token_1.hashInvitationToken)(rawToken);
        const expiresAt = new Date(Date.now() + (request.expiresInHours ?? 72) * 60 * 60 * 1000);
        const invitation = await db_1.prisma.invitation.create({
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
            status: invitation.status,
            expiresAtUtc: invitation.expiresAt.toISOString(),
            inviteUrl: `${process.env.WEB_APP_URL}/invite/${rawToken}`,
        };
    }
    async getInvitationByToken(rawToken) {
        const tokenHash = (0, invitation_token_1.hashInvitationToken)(rawToken);
        const invitation = await db_1.prisma.invitation.findUnique({ where: { tokenHash } });
        if (!invitation) {
            throw new api_error_1.ApiError({ statusCode: 404, code: "INVITATION_NOT_FOUND", message: "Invitation not found." });
        }
        if (invitation.expiresAt.getTime() < Date.now() && invitation.status === "PENDING") {
            await db_1.prisma.invitation.update({ where: { id: invitation.id }, data: { status: "EXPIRED" } });
            throw new api_error_1.ApiError({ statusCode: 410, code: "INVITATION_EXPIRED", message: "Invitation has expired." });
        }
        return {
            invitationId: invitation.id,
            email: invitation.email,
            invitationType: invitation.invitationType,
            targetRoleCode: invitation.targetRoleCode,
            partnerOrganizationId: invitation.partnerOrganizationId,
            advisorUserId: invitation.advisorUserId,
            status: invitation.status,
            expiresAtUtc: invitation.expiresAt.toISOString(),
        };
    }
    async acceptInvitation(rawToken, acceptedUserId) {
        const tokenHash = (0, invitation_token_1.hashInvitationToken)(rawToken);
        const invitation = await db_1.prisma.invitation.findUnique({ where: { tokenHash } });
        if (!invitation || invitation.status !== "PENDING") {
            throw new api_error_1.ApiError({ statusCode: 400, code: "INVITATION_NOT_ACCEPTABLE", message: "Invitation cannot be accepted." });
        }
        const updated = await db_1.prisma.invitation.update({
            where: { id: invitation.id },
            data: { status: "ACCEPTED", acceptedAt: new Date(), acceptedUserId },
        });
        if (updated.advisorUserId && updated.targetRoleCode === "CLIENT") {
            await db_1.prisma.advisorClientAssignment.create({
                data: { advisorUserId: updated.advisorUserId, clientUserId: acceptedUserId, status: "ACTIVE" },
            });
        }
        return {
            invitationId: updated.id,
            status: "ACCEPTED",
            acceptedAtUtc: updated.acceptedAt.toISOString(),
        };
    }
}
exports.invitationsService = new InvitationsService();
