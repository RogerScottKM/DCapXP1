import { apiFetch } from "./client";

export const PENDING_REFERRAL_CODE_STORAGE_KEY = "dcapx_pending_referral_code";
export const REFERRAL_APPLY_FEEDBACK_STORAGE_KEY = "dcapx_referral_apply_feedback";

export interface ReferralApplyFeedback {
  kind: "success" | "error";
  message: string;
}

export interface ReferralRewardBalanceDto {
  unitType: "POINTS" | "CASH" | "TOKEN" | "PROFIT_SHARE" | "STOCK_OPTION";
  balance: number;
  updatedAtUtc: string | null;
}

export interface ReferralAttributionDto {
  id: string;
  status: "PENDING" | "CONFIRMED" | "REJECTED" | "CANCELLED";
  applySource: "LOGIN" | "ONBOARDING" | "INVITATION" | "REGISTER" | "ADMIN" | "IMPORT" | null;
  referralCode: string;
  referrerUserId: string;
  attributedAtUtc: string;
  confirmedAtUtc: string | null;
  communityKey: string | null;
  regionKey: string | null;
}

export interface GetMyReferralStatusResponse {
  hasAttribution: boolean;
  canApplyReferralCode: boolean;
  lockedReason: string | null;
  referredByCodeInput: string | null;
  attribution: ReferralAttributionDto | null;
  rewards: {
    balances: ReferralRewardBalanceDto[];
    totals: {
      points: number;
      cash: number;
      token: number;
      profitShare: number;
      stockOption: number;
    };
  };
}

export interface ApplyReferralCodeRequest {
  code: string;
  applySource?: "LOGIN" | "ONBOARDING" | "INVITATION" | "REGISTER" | "ADMIN" | "IMPORT";
}

export interface ApplyReferralCodeResponse {
  ok: true;
  message: string;
  status: GetMyReferralStatusResponse;
}

export function applyReferralCode(body: ApplyReferralCodeRequest) {
  return apiFetch<ApplyReferralCodeResponse>("/api/referrals/apply", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function getMyReferralStatus() {
  return apiFetch<GetMyReferralStatusResponse>("/api/me/referral-status");
}

export function setReferralApplyFeedback(feedback: ReferralApplyFeedback) {
  if (typeof window === "undefined") return;
  sessionStorage.setItem(
    REFERRAL_APPLY_FEEDBACK_STORAGE_KEY,
    JSON.stringify(feedback)
  );
}

export function popReferralApplyFeedback(): ReferralApplyFeedback | null {
  if (typeof window === "undefined") return null;

  const raw = sessionStorage.getItem(REFERRAL_APPLY_FEEDBACK_STORAGE_KEY);
  if (!raw) return null;

  sessionStorage.removeItem(REFERRAL_APPLY_FEEDBACK_STORAGE_KEY);

  try {
    return JSON.parse(raw) as ReferralApplyFeedback;
  } catch {
    return null;
  }
}
