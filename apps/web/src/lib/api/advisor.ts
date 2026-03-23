import type { AdvisorAptivioSummaryResponse } from "@dcapx/contracts";
import { apiFetch } from "./client";

export function getAdvisorClientAptivioSummary(clientId: string) {
  return apiFetch<AdvisorAptivioSummaryResponse>(`/api/advisor/clients/${clientId}/aptivio-summary`);
}
