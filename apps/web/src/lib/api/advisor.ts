import { apiFetch } from "./client";
import type { AdvisorAptivioSummaryResponse } from "@dcapx/contracts";

export function getAdvisorClientAptivioSummary(clientId: string) {
  return apiFetch<AdvisorAptivioSummaryResponse>(
    `/api/advisor/clients/${clientId}/aptivio-summary`
  );
}
