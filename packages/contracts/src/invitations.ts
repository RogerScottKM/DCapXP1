import type { UtcIsoString } from "./common";
export type InvitationType = "CLIENT_ONBOARDING" | "ADVISOR_JOIN" | "PARTNER_OPERATOR_JOIN";
export type InvitationStatus = "PENDING" | "ACCEPTED" | "EXPIRED" | "REVOKED";
export interface CreateInvitationRequest { email: string; invitationType: InvitationType; targetRoleCode: string; partnerOrganizationId?: string | null; advisorUserId?: string | null; expiresInHours?: number; }
export interface CreateInvitationResponse { invitationId: string; status: InvitationStatus; expiresAtUtc: UtcIsoString; inviteUrl: string; }
export interface GetInvitationByTokenResponse { invitationId: string; email: string; invitationType: InvitationType; targetRoleCode: string; partnerOrganizationId: string | null; advisorUserId: string | null; status: InvitationStatus; expiresAtUtc: UtcIsoString; }
export interface AcceptInvitationRequest { accept: true; }
export interface AcceptInvitationResponse { invitationId: string; status: "ACCEPTED"; acceptedAtUtc: UtcIsoString; }
