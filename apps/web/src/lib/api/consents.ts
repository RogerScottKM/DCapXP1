import type {
  AcceptConsentsRequest,
  ConsentRecordDto,
  GetRequiredConsentsResponse,
} from "@dcapx/contracts";
import { apiFetch } from "./client";

export function getRequiredConsents() {
  return apiFetch<GetRequiredConsentsResponse>("/api/me/required-consents");
}

export function acceptConsents(body: AcceptConsentsRequest) {
  return apiFetch<ConsentRecordDto[]>("/api/me/consents", {
    method: "POST",
    body: JSON.stringify(body),
  });
}
