import type { OnboardingStatusResponse } from "@dcapx/contracts";
import { apiFetch } from "./client";

export function getMyOnboardingStatus() {
  return apiFetch<OnboardingStatusResponse>("/api/me/onboarding-status");
}
