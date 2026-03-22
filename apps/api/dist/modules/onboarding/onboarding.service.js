"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onboardingService = void 0;
const db_1 = require("../../db");
const utc_1 = require("../../lib/time/utc");
const onboarding_mapper_1 = require("./onboarding.mapper");
const REQUIRED_CONSENTS = [
    "TERMS_OF_SERVICE",
    "PRIVACY_POLICY",
    "DATA_PROCESSING",
    "ELECTRONIC_COMMUNICATION",
    "APTIVIO_ASSESSMENT_AUTH",
];
class OnboardingService {
    async getMyOnboardingStatus(userId) {
        const [user, consents, latestKycCase, paymentMethodCount, latestWalletWhitelist, latestAssessmentRun, aptivioProfile, advisorAssignment,] = await Promise.all([
            db_1.prisma.user.findUnique({
                where: { id: userId },
                include: {
                    profile: true,
                },
            }),
            db_1.prisma.consentRecord.findMany({
                where: { userId, revokedAt: null },
                orderBy: { acceptedAt: "desc" },
            }),
            db_1.prisma.kycCase.findFirst({
                where: { userId },
                orderBy: { createdAt: "desc" },
            }),
            db_1.prisma.paymentMethod.count({
                where: { userId },
            }),
            db_1.prisma.walletWhitelistEntry.findFirst({
                where: { userId },
                orderBy: { createdAt: "desc" },
            }),
            db_1.prisma.assessmentRun.findFirst({
                where: { userId },
                orderBy: { createdAt: "desc" },
            }),
            db_1.prisma.aptivioProfile.findUnique({
                where: { userId },
                include: { aptivioId: true },
            }),
            db_1.prisma.advisorClientAssignment.findFirst({
                where: { clientUserId: userId, status: "ACTIVE" },
                orderBy: { createdAt: "desc" },
            }),
        ]);
        const aptivioIdentity = aptivioProfile?.aptivioId ?? null;
        const acceptedConsentTypes = Array.from(new Set(consents.map((c) => c.consentType)));
        const hasAllRequiredConsents = REQUIRED_CONSENTS.every((type) => acceptedConsentTypes.includes(type));
        const profileComplete = Boolean(user &&
            user?.profile?.firstName &&
            user?.profile?.lastName &&
            user?.email &&
            user?.phone &&
            user?.profile?.country);
        const kycSubmitted = Boolean(latestKycCase);
        const kycApproved = latestKycCase?.status === "APPROVED";
        const kycInProgress = latestKycCase?.status === "SUBMITTED" || latestKycCase?.status === "UNDER_REVIEW";
        const kycFailed = latestKycCase?.status === "REJECTED" || latestKycCase?.status === "NEEDS_INFO";
        const walletApproved = latestWalletWhitelist?.status === "WHITELISTED" ||
            latestWalletWhitelist?.status === "ACTIVE";
        const walletInProgress = latestWalletWhitelist?.status === "PENDING_VERIFICATION" ||
            latestWalletWhitelist?.status === "COOLDOWN";
        const assessmentCompleted = latestAssessmentRun?.status === "SCORED";
        const aptivioIssued = Boolean(aptivioIdentity?.issuedAt);
        const advisorLinked = Boolean(advisorAssignment);
        const steps = [
            (0, onboarding_mapper_1.makeStep)("ACCOUNT_CREATED", "Account created", user ? "COMPLETED" : "NOT_STARTED", true, (0, utc_1.toUtcIso)(user?.createdAt)),
            (0, onboarding_mapper_1.makeStep)("CONTACT_VERIFIED", "OTP verified", user?.phoneVerifiedAt || user?.emailVerifiedAt ? "COMPLETED" : "NOT_STARTED", true, (0, utc_1.toUtcIso)(user?.phoneVerifiedAt || user?.emailVerifiedAt)),
            (0, onboarding_mapper_1.makeStep)("CONSENTS_ACCEPTED", "Required consents accepted", hasAllRequiredConsents ? "COMPLETED" : acceptedConsentTypes.length ? "IN_PROGRESS" : "NOT_STARTED", true, consents.length ? (0, utc_1.toUtcIso)(consents[0].acceptedAt) : null, {
                requiredConsentTypes: REQUIRED_CONSENTS,
                acceptedConsentTypes,
            }),
            (0, onboarding_mapper_1.makeStep)("PROFILE_COMPLETED", "Profile completed", profileComplete ? "COMPLETED" : "IN_PROGRESS", true),
            (0, onboarding_mapper_1.makeStep)("KYC_SUBMITTED", "KYC submitted", kycSubmitted ? "COMPLETED" : "NOT_STARTED", true, (0, utc_1.toUtcIso)(latestKycCase?.createdAt), latestKycCase ? { caseStatus: latestKycCase.status, kycCaseId: latestKycCase.id } : undefined),
            (0, onboarding_mapper_1.makeStep)("KYC_APPROVED", "KYC approved", kycApproved ? "COMPLETED" : kycFailed ? "FAILED" : kycInProgress ? "IN_PROGRESS" : "NOT_STARTED", true, (0, utc_1.toUtcIso)(latestKycCase?.updatedAt), latestKycCase ? { caseStatus: latestKycCase.status } : undefined),
            (0, onboarding_mapper_1.makeStep)("PAYMENT_METHOD_ADDED", "Payment method added", paymentMethodCount > 0 ? "COMPLETED" : "NOT_STARTED", false),
            (0, onboarding_mapper_1.makeStep)("WALLET_WHITELIST_APPROVED", "Wallet approved", walletApproved ? "COMPLETED" : walletInProgress ? "IN_PROGRESS" : "NOT_STARTED", false, (0, utc_1.toUtcIso)(latestWalletWhitelist?.approvedAt ?? latestWalletWhitelist?.createdAt), latestWalletWhitelist ? { status: latestWalletWhitelist.status } : undefined),
            (0, onboarding_mapper_1.makeStep)("APTIVIO_ASSESSMENT_COMPLETED", "Aptivio assessment completed", assessmentCompleted ? "COMPLETED" : latestAssessmentRun ? "IN_PROGRESS" : "NOT_STARTED", true, (0, utc_1.toUtcIso)(latestAssessmentRun?.scoredAt || latestAssessmentRun?.submittedAt)),
            (0, onboarding_mapper_1.makeStep)("APTIVIO_ID_ISSUED", "Aptivio ID issued", aptivioIssued ? "COMPLETED" : aptivioProfile ? "IN_PROGRESS" : "NOT_STARTED", true, (0, utc_1.toUtcIso)(aptivioIdentity?.issuedAt)),
            (0, onboarding_mapper_1.makeStep)("ADVISOR_LINKED", "Advisor linked", advisorLinked ? "COMPLETED" : "NOT_STARTED", false, (0, utc_1.toUtcIso)(advisorAssignment?.createdAt), advisorAssignment ? { advisorUserId: advisorAssignment.advisorUserId } : undefined),
            (0, onboarding_mapper_1.makeStep)("DIGITAL_TWIN_ENABLED", "Digital twin enabled", aptivioIssued ? "IN_PROGRESS" : "LOCKED", false),
        ];
        const overallStatus = (0, onboarding_mapper_1.deriveOverallStatus)(steps);
        const completionPercent = (0, onboarding_mapper_1.deriveCompletionPercent)(steps);
        const currentStep = steps.find((s) => s.required && s.status !== "COMPLETED")?.code ?? null;
        const nextRecommendedAction = currentStep === "CONSENTS_ACCEPTED"
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
                    acceptedConsentTypes: acceptedConsentTypes,
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
                    issuedAtUtc: (0, utc_1.toUtcIso)(aptivioIdentity?.issuedAt),
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
exports.onboardingService = new OnboardingService();
