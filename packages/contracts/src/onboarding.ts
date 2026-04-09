import type { UtcIsoString } from "./common"; import type { ConsentType } from "./consents";

export type OnboardingStepCode =
  | "ACCOUNT_CREATED"
  | "CONTACT_VERIFIED"
  | "REFERRAL_CODE_APPLIED"
  | "CONSENTS_ACCEPTED"
  | "PROFILE_COMPLETED"
  | "KYC_SUBMITTED"
  | "KYC_APPROVED"
  | "PAYMENT_METHOD_ADDED"
  | "WALLET_WHITELIST_APPROVED"
  | "APTIVIO_ASSESSMENT_COMPLETED"
  | "APTIVIO_ID_ISSUED"
  | "ADVISOR_LINKED"
  | "DIGITAL_TWIN_ENABLED";

export type OnboardingStepStatus = "NOT_STARTED" | "IN_PROGRESS" | "COMPLETED" | "FAILED" | "BLOCKED" | "LOCKED";
export type OnboardingOverallStatus = "NOT_STARTED" | "IN_PROGRESS" | "PENDING_REVIEW" | "ACTION_REQUIRED" | "COMPLETED";
export interface OnboardingStepDto { code: OnboardingStepCode; label: string; status: OnboardingStepStatus; required: boolean; completedAtUtc?: UtcIsoString | null; details?: Record<string, unknown>; }
export interface OnboardingReferralEntity {
  canApplyReferralCode: boolean;
  referredByCodeInput: string | null;
  appliedCode: string | null;
  referrerUserId: string | null;
  attributionStatus: "PENDING" | "CONFIRMED" | "REJECTED" | "CANCELLED" | null;
  pointsBalance: number | null;
}

export interface OnboardingStatusResponse {
  userId: string;
  overallStatus: OnboardingOverallStatus;
  completionPercent: number;
  currentStep: OnboardingStepCode | null;
  nextRecommendedAction: {
    code: string;
    label: string;
    path: string;
  } | null;
  steps: OnboardingStepDto[];
  entities: {
    requiredConsents: {
      requiredConsentTypes: ConsentType[];
      acceptedConsentTypes: ConsentType[];
    };
    kycCase: {
      id: string | null;
      status: string | null;
    };
    walletWhitelist: {
      latestStatus: string | null;
    };
    assessment: {
      latestRunId: string | null;
      status: string | null;
    };
    aptivioProfile: {
      status: string | null;
    };
    aptivioIdentity: {
      issued: boolean;
      issuedAtUtc: UtcIsoString | null;
    };
    advisorAssignment: {
      assigned: boolean;
      advisorUserId: string | null;
    };
    referral: OnboardingReferralEntity;
  };
  updatedAtUtc: UtcIsoString;
};
