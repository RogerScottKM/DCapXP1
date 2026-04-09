import { apiFetch } from "./client";
import type {
  AcceptInvitationRequest,
  AcceptInvitationResponse,
  GetInvitationByTokenResponse,
} from "@dcapx/contracts";

export function getInvitationByToken(token: string) {
  return apiFetch<GetInvitationByTokenResponse>(`/api/invitations/${token}`);
}

export function acceptInvitation(token: string, body: AcceptInvitationRequest) {
  return apiFetch<AcceptInvitationResponse>(`/api/invitations/${token}/accept`, {
    method: "POST",
    body: JSON.stringify(body),
  });
}
