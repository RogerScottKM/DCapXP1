import { prisma } from "../../db";
import { toUtcIso } from "../../lib/time/utc";
import { deriveCompletionPercent, deriveOverallStatus, makeStep } from "./onboarding.mapper";
import type { OnboardingStatusResponse } from "@dcapx/contracts";

const REQUIRED_CONSENTS = [
  "TERMS_OF_SERVICE",
  "PRIVACY_POLICY",
  "DATA_PROCESSING",
  "ELECTRONIC_COMMUNICATION",
  "APTIVIO_ASSESSMENT_AUTH",
] as const;

class OnboardingService {
  async getMyOnboardingStatus(userId: string): Promise<OnboardingStatusResponse> {

   const [
  user,
  consents,
  latestKycCase,
  paymentMethodCount,
  latestWalletWhitelist,
  latestAssessmentRun,
  aptivioProfile,
  advisorAssignment,
] = await Promise.all([
  prisma.user.findUnique({
    where: { id: userId },
    include: {
      profile: true,
    },
  }),
  prisma.consentRecord.findMany({
    where: { userId, revokedAt: null },
    orderBy: { acceptedAt: "desc" },
  }),
  prisma.kycCase.findFirst({
    where: { userId },
    orderBy: { createdAt: "desc" },
  }),
  prisma.paymentMethod.count({
    where: { userId },
  }),
  prisma.walletWhitelistEntry.findFirst({
    where: { userId },
    orderBy: { createdAt: "desc" },
  }),
  prisma.assessmentRun.findFirst({
    where: { userId },
    orderBy: { createdAt: "desc" },
  }),
  prisma.aptivioProfile.findUnique({
    where: { userId },
    include: { aptivioId: true },
  }),
  prisma.advisorClientAssignment.findFirst({
    where: { clientUserId: userId, status: "ACTIVE" },
    orderBy: { createdAt: "desc" },
  }),
]);

const aptivioIdentity = aptivioProfile?.aptivioId ?? null;

    const acceptedConsentTypes = Array.from(new Set(consents.map((c) => c.consentType)));
    const hasAllRequiredConsents = REQUIRED_CONSENTS.every((type) =>
      acceptedConsentTypes.includes(type as any)
    );
    const profileComplete = Boolean(
      user &&
        user?.profile?.firstName &&
    user?.profile?.lastName &&
    user?.email &&
    user?.phone &&
    user?.profile?.country
    );
    const kycSubmitted = Boolean(latestKycCase);
    const kycApproved = latestKycCase?.status === "APPROVED";
    const kycInProgress =
      latestKycCase?.status === "SUBMITTED" || latestKycCase?.status === "UNDER_REVIEW";
    const kycFailed =
      latestKycCase?.status === "REJECTED" || latestKycCase?.status === "NEEDS_INFO";
    const walletApproved =
  latestWalletWhitelist?.status === "WHITELISTED" ||
  latestWalletWhitelist?.status === "ACTIVE";

    const walletInProgress =
  latestWalletWhitelist?.status === "PENDING_VERIFICATION" ||
  latestWalletWhitelist?.status === "COOLDOWN";


    const assessmentCompleted = latestAssessmentRun?.status === "SCORED";
    const aptivioIssued = Boolean(aptivioIdentity?.issuedAt);
    const advisorLinked = Boolean(advisorAssignment);

    const steps = [
      makeStep(
        "ACCOUNT_CREATED",
        "Account created",
        user ? "COMPLETED" : "NOT_STARTED",
        true,
        toUtcIso(user?.createdAt)
      ),
      makeStep(
        "CONTACT_VERIFIED",
        "OTP verified",
        user?.phoneVerifiedAt || user?.emailVerifiedAt ? "COMPLETED" : "NOT_STARTED",
        true,
        toUtcIso(user?.phoneVerifiedAt || user?.emailVerifiedAt)
      ),
      makeStep(
        "CONSENTS_ACCEPTED",
        "Required consents accepted",
        hasAllRequiredConsents ? "COMPLETED" : acceptedConsentTypes.length ? "IN_PROGRESS" : "NOT_STARTED",
        true,
        consents.length ? toUtcIso(consents[0].acceptedAt) : null,
        {
          requiredConsentTypes: REQUIRED_CONSENTS,
          acceptedConsentTypes,
        }
      ),
      makeStep(
        "PROFILE_COMPLETED",
        "Profile completed",
        profileComplete ? "COMPLETED" : "IN_PROGRESS",
        true
      ),
      makeStep(
        "KYC_SUBMITTED",
        "KYC submitted",
        kycSubmitted ? "COMPLETED" : "NOT_STARTED",
        true,
        toUtcIso(latestKycCase?.createdAt),
        latestKycCase ? { caseStatus: latestKycCase.status, kycCaseId: latestKycCase.id } : undefined
      ),
      makeStep(
        "KYC_APPROVED",
        "KYC approved",
        kycApproved ? "COMPLETED" : kycFailed ? "FAILED" : kycInProgress ? "IN_PROGRESS" : "NOT_STARTED",
        true,
        toUtcIso(latestKycCase?.updatedAt),
        latestKycCase ? { caseStatus: latestKycCase.status } : undefined
      ),
      makeStep(
        "PAYMENT_METHOD_ADDED",
        "Payment method added",
        paymentMethodCount > 0 ? "COMPLETED" : "NOT_STARTED",
        false
      ),
      makeStep(
        "WALLET_WHITELIST_APPROVED",
        "Wallet approved",
        walletApproved ? "COMPLETED" : walletInProgress ? "IN_PROGRESS" : "NOT_STARTED",
        false,
        toUtcIso(latestWalletWhitelist?.approvedAt ?? latestWalletWhitelist?.createdAt),
        latestWalletWhitelist ? { status: latestWalletWhitelist.status } : undefined
      ),
      makeStep(
        "APTIVIO_ASSESSMENT_COMPLETED",
        "Aptivio assessment completed",
        assessmentCompleted ? "COMPLETED" : latestAssessmentRun ? "IN_PROGRESS" : "NOT_STARTED",
        true,
        toUtcIso(latestAssessmentRun?.scoredAt || latestAssessmentRun?.submittedAt)
      ),
      makeStep(
        "APTIVIO_ID_ISSUED",
        "Aptivio ID issued",
        aptivioIssued ? "COMPLETED" : aptivioProfile ? "IN_PROGRESS" : "NOT_STARTED",
        true,
        toUtcIso(aptivioIdentity?.issuedAt)
      ),
      makeStep(
        "ADVISOR_LINKED",
        "Advisor linked",
        advisorLinked ? "COMPLETED" : "NOT_STARTED",
        false,
        toUtcIso(advisorAssignment?.createdAt),
        advisorAssignment ? { advisorUserId: advisorAssignment.advisorUserId } : undefined
      ),
      makeStep(
        "DIGITAL_TWIN_ENABLED",
        "Digital twin enabled",
        aptivioIssued ? "IN_PROGRESS" : "LOCKED",
        false
      ),
    ];

    const overallStatus = deriveOverallStatus(steps);
    const completionPercent = deriveCompletionPercent(steps);
    const currentStep =
      steps.find((s) => s.required && s.status !== "COMPLETED")?.code ?? null;
    const nextRecommendedAction =
      currentStep === "CONSENTS_ACCEPTED"
        ? { code: "COMPLETE_CONSENTS", label: "Accept required consents", path: "/app/consents" }
        : currentStep === "PROFILE_COMPLETED"
        ? { code: "COMPLETE_PROFILE", label: "Complete your profile", path: "/app/profile" }
        : currentStep === "KYC_SUBMITTED" || currentStep === "KYC_APPROVED"
        ? { code: "VISIT_KYC", label: "Review your KYC status", path: "/app/kyc" }
        : currentStep === "APTIVIO_ASSESSMENT_COMPLETED"
        ? { code: "START_APTIVIO", label: "Complete Aptivio assessment", path: "/app/aptivio" }
        : null;

    return {
      userId,
      overallStatus,
      completionPercent,
      currentStep,
      nextRecommendedAction,
      steps,
      entities: {
        requiredConsents: {
          requiredConsentTypes: [...REQUIRED_CONSENTS],
          acceptedConsentTypes: acceptedConsentTypes as any,
        },
        kycCase: {
          id: latestKycCase?.id ?? null,
          status: latestKycCase?.status ?? null,
        },
        walletWhitelist: {
          latestStatus: latestWalletWhitelist?.status ?? null,
        },
        assessment: {
          latestRunId: latestAssessmentRun?.id ?? null,
          status: latestAssessmentRun?.status ?? null,
        },
        aptivioProfile: {
          status: aptivioProfile?.status ?? null,
        },
        aptivioIdentity: {
          issued: Boolean(aptivioIdentity),
          issuedAtUtc: toUtcIso(aptivioIdentity?.issuedAt),
        },
        advisorAssignment: {
          assigned: advisorLinked,
          advisorUserId: advisorAssignment?.advisorUserId ?? null,
        },
      },
      updatedAtUtc: new Date().toISOString(),
    };
  }
}
export const onboardingService = new OnboardingService();
