/*
  Warnings:

  - A unique constraint covering the columns `[keyHash]` on the table `AgentKey` will be added. If there are existing duplicate values, this will fail.
  - A unique constraint covering the columns `[phone]` on the table `User` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('INVITED', 'REGISTERED', 'OTP_VERIFIED', 'ACTIVE', 'SUSPENDED', 'CLOSED');

-- CreateEnum
CREATE TYPE "RoleCode" AS ENUM ('USER', 'ADVISOR', 'COMPLIANCE', 'ADMIN', 'AUDITOR', 'PARTNER_ADMIN', 'BANK_OPERATOR', 'SYSTEM_AGENT');

-- CreateEnum
CREATE TYPE "OtpPurpose" AS ENUM ('REGISTER', 'VERIFY_EMAIL', 'VERIFY_PHONE', 'LOGIN', 'MFA', 'RESET_PASSWORD');

-- CreateEnum
CREATE TYPE "OtpChannel" AS ENUM ('EMAIL', 'SMS');

-- CreateEnum
CREATE TYPE "MfaFactorType" AS ENUM ('TOTP');

-- CreateEnum
CREATE TYPE "MfaFactorStatus" AS ENUM ('PENDING', 'ACTIVE', 'REVOKED');

-- CreateEnum
CREATE TYPE "KycCaseStatus" AS ENUM ('NOT_STARTED', 'IN_PROGRESS', 'SUBMITTED', 'UNDER_REVIEW', 'NEEDS_INFO', 'APPROVED', 'REJECTED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "KycDocumentType" AS ENUM ('PASSPORT', 'NATIONAL_ID', 'DRIVER_LICENSE', 'SELFIE', 'PROOF_OF_ADDRESS', 'BUSINESS_REGISTRATION', 'OTHER');

-- CreateEnum
CREATE TYPE "KycDecisionCode" AS ENUM ('APPROVE', 'REJECT', 'REQUEST_INFO');

-- CreateEnum
CREATE TYPE "PaymentMethodType" AS ENUM ('BANK_ACCOUNT', 'STRIPE_CUSTOMER', 'PAYPAL_ACCOUNT', 'VENMO_ACCOUNT', 'OTHER');

-- CreateEnum
CREATE TYPE "PaymentMethodStatus" AS ENUM ('ADDED', 'PENDING_VERIFICATION', 'VERIFIED', 'RESTRICTED', 'DISABLED');

-- CreateEnum
CREATE TYPE "WalletType" AS ENUM ('CUSTODIAL', 'EXTERNAL');

-- CreateEnum
CREATE TYPE "WalletStatus" AS ENUM ('CREATED', 'PENDING_VERIFICATION', 'WHITELISTED', 'COOLDOWN', 'ACTIVE', 'FROZEN', 'REVOKED');

-- CreateEnum
CREATE TYPE "PartnerOrgType" AS ENUM ('ADVISORY_FIRM', 'BANK', 'ISSUER', 'EMPLOYER', 'OTHER');

-- CreateEnum
CREATE TYPE "AssessmentRunStatus" AS ENUM ('PENDING', 'RUNNING', 'COMPLETED', 'FAILED');

-- CreateEnum
CREATE TYPE "AptivioProfileStatus" AS ENUM ('DRAFT', 'ASSESSMENT_PENDING', 'ACTIVE', 'RESTRICTED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "AgentCredentialType" AS ENUM ('PUBLIC_KEY', 'API_KEY');

-- CreateEnum
CREATE TYPE "AgentCapabilityTier" AS ENUM ('READ_ONLY', 'RECOMMEND_ONLY', 'PLAN_ONLY', 'EXECUTE_TRADE');

-- CreateEnum
CREATE TYPE "AgentPrincipalType" AS ENUM ('DIGITAL_TWIN', 'TRADING_AGENT', 'COMPLIANCE_AGENT', 'ADVISOR_AGENT', 'INTERNAL_MM');

-- AlterEnum
ALTER TYPE "AgentStatus" ADD VALUE 'DRAFT';

-- DropForeignKey
ALTER TABLE "Agent" DROP CONSTRAINT "Agent_userId_fkey";

-- DropForeignKey
ALTER TABLE "AgentKey" DROP CONSTRAINT "AgentKey_agentId_fkey";

-- DropForeignKey
ALTER TABLE "Balance" DROP CONSTRAINT "Balance_userId_fkey";

-- DropForeignKey
ALTER TABLE "Kyc" DROP CONSTRAINT "Kyc_userId_fkey";

-- DropForeignKey
ALTER TABLE "Mandate" DROP CONSTRAINT "Mandate_agentId_fkey";

-- DropForeignKey
ALTER TABLE "MandateUsage" DROP CONSTRAINT "MandateUsage_mandateId_fkey";

-- AlterTable
ALTER TABLE "Agent" ADD COLUMN     "capabilityTier" "AgentCapabilityTier" NOT NULL DEFAULT 'READ_ONLY',
ADD COLUMN     "principalType" "AgentPrincipalType";

-- AlterTable
ALTER TABLE "AgentKey" ADD COLUMN     "credentialType" "AgentCredentialType" NOT NULL DEFAULT 'PUBLIC_KEY',
ADD COLUMN     "expiresAt" TIMESTAMP(3),
ADD COLUMN     "keyHash" TEXT,
ADD COLUMN     "keyPrefix" TEXT,
ALTER COLUMN "publicKeyPem" DROP NOT NULL;

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "emailVerifiedAt" TIMESTAMP(3),
ADD COLUMN     "phone" TEXT,
ADD COLUMN     "phoneVerifiedAt" TIMESTAMP(3),
ADD COLUMN     "status" "UserStatus" NOT NULL DEFAULT 'REGISTERED';

-- CreateTable
CREATE TABLE "UserProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "firstName" TEXT NOT NULL,
    "lastName" TEXT NOT NULL,
    "fullName" TEXT,
    "dateOfBirth" TIMESTAMP(3),
    "country" TEXT,
    "residency" TEXT,
    "nationality" TEXT,
    "addressLine1" TEXT,
    "addressLine2" TEXT,
    "city" TEXT,
    "state" TEXT,
    "postalCode" TEXT,
    "employerName" TEXT,
    "sourceChannel" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UserProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Session" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "refreshTokenHash" TEXT NOT NULL,
    "ipAddress" TEXT,
    "userAgent" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OtpChallenge" (
    "id" TEXT NOT NULL,
    "userId" TEXT,
    "purpose" "OtpPurpose" NOT NULL,
    "channel" "OtpChannel" NOT NULL,
    "target" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OtpChallenge_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MfaFactor" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "MfaFactorType" NOT NULL,
    "status" "MfaFactorStatus" NOT NULL DEFAULT 'PENDING',
    "label" TEXT,
    "secretEncrypted" TEXT NOT NULL,
    "activatedAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MfaFactor_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RoleAssignment" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "roleCode" "RoleCode" NOT NULL,
    "scopeType" TEXT,
    "scopeId" TEXT,
    "assignedByUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RoleAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConsentRecord" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "consentType" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "metadata" JSONB,

    CONSTRAINT "ConsentRecord_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "KycCase" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "KycCaseStatus" NOT NULL DEFAULT 'NOT_STARTED',
    "providerRef" TEXT,
    "notes" TEXT,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "submittedAt" TIMESTAMP(3),
    "reviewedAt" TIMESTAMP(3),
    "reviewerUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "KycCase_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "KycDocument" (
    "id" TEXT NOT NULL,
    "kycCaseId" TEXT NOT NULL,
    "docType" "KycDocumentType" NOT NULL,
    "fileKey" TEXT NOT NULL,
    "fileName" TEXT,
    "mimeType" TEXT,
    "uploadedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "metadata" JSONB,

    CONSTRAINT "KycDocument_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "KycDecision" (
    "id" TEXT NOT NULL,
    "kycCaseId" TEXT NOT NULL,
    "decision" "KycDecisionCode" NOT NULL,
    "reasonCode" TEXT,
    "notes" TEXT,
    "reviewerUserId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "KycDecision_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ScreeningResult" (
    "id" TEXT NOT NULL,
    "kycCaseId" TEXT NOT NULL,
    "screeningType" TEXT NOT NULL,
    "result" TEXT NOT NULL,
    "score" DECIMAL(10,4),
    "payload" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ScreeningResult_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PaymentMethod" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "PaymentMethodType" NOT NULL,
    "status" "PaymentMethodStatus" NOT NULL DEFAULT 'ADDED',
    "label" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PaymentMethod_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BankAccount" (
    "id" TEXT NOT NULL,
    "paymentMethodId" TEXT NOT NULL,
    "accountHolderName" TEXT NOT NULL,
    "bankName" TEXT NOT NULL,
    "country" TEXT,
    "currency" TEXT,
    "maskedAccountNumber" TEXT,
    "maskedRoutingNumber" TEXT,
    "ibanMasked" TEXT,
    "swiftBicMasked" TEXT,
    "verifiedAt" TIMESTAMP(3),
    "metadata" JSONB,

    CONSTRAINT "BankAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Wallet" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "WalletType" NOT NULL,
    "status" "WalletStatus" NOT NULL DEFAULT 'CREATED',
    "chain" TEXT,
    "address" TEXT,
    "label" TEXT,
    "isCustodial" BOOLEAN NOT NULL DEFAULT false,
    "verifiedAt" TIMESTAMP(3),
    "activatedAt" TIMESTAMP(3),
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Wallet_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WalletWhitelistEntry" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "chain" TEXT NOT NULL,
    "address" TEXT NOT NULL,
    "label" TEXT,
    "status" "WalletStatus" NOT NULL DEFAULT 'PENDING_VERIFICATION',
    "approvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WalletWhitelistEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PartnerOrganization" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" "PartnerOrgType" NOT NULL,
    "country" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PartnerOrganization_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdvisorProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "organizationId" TEXT,
    "licenseNumber" TEXT,
    "status" TEXT,
    "specialties" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AdvisorProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdvisorClientAssignment" (
    "id" TEXT NOT NULL,
    "advisorUserId" TEXT NOT NULL,
    "clientUserId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AdvisorClientAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AptitudeDefinition" (
    "id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "orderIndex" INTEGER NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AptitudeDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AptivioProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "AptivioProfileStatus" NOT NULL DEFAULT 'DRAFT',
    "score" INTEGER,
    "aptitudeVector" JSONB,
    "twinJson" JSONB,
    "skillPassportJson" JSONB,
    "professionalismJson" JSONB,
    "trajectoryJson" JSONB,
    "riskProfileJson" JSONB,
    "version" TEXT NOT NULL DEFAULT 'v1.0.0',
    "lastAssessedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AptivioProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AssessmentRun" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "aptivioProfileId" TEXT NOT NULL,
    "assessmentType" TEXT NOT NULL,
    "status" "AssessmentRunStatus" NOT NULL DEFAULT 'PENDING',
    "rawResultJson" JSONB,
    "normalizedJson" JSONB,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AssessmentRun_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AssessmentAptitudeScore" (
    "id" TEXT NOT NULL,
    "assessmentRunId" TEXT NOT NULL,
    "aptitudeDefinitionId" TEXT NOT NULL,
    "score" INTEGER NOT NULL,
    "confidence" DECIMAL(5,4),
    "weightForRole" DECIMAL(5,4),
    "lastAssessedAt" TIMESTAMP(3),
    "sourcesJson" JSONB,

    CONSTRAINT "AssessmentAptitudeScore_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AptivioIdentity" (
    "id" TEXT NOT NULL,
    "aptivioProfileId" TEXT NOT NULL,
    "passportNumber" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "issuedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimsJson" JSONB,
    "tokenEntitlementsJson" JSONB,

    CONSTRAINT "AptivioIdentity_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEvent" (
    "id" TEXT NOT NULL,
    "actorType" TEXT NOT NULL,
    "actorId" TEXT,
    "subjectType" TEXT,
    "subjectId" TEXT,
    "action" TEXT NOT NULL,
    "resourceType" TEXT,
    "resourceId" TEXT,
    "ipAddress" TEXT,
    "userAgent" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "UserProfile_userId_key" ON "UserProfile"("userId");

-- CreateIndex
CREATE INDEX "Session_userId_expiresAt_idx" ON "Session"("userId", "expiresAt");

-- CreateIndex
CREATE INDEX "OtpChallenge_target_purpose_expiresAt_idx" ON "OtpChallenge"("target", "purpose", "expiresAt");

-- CreateIndex
CREATE INDEX "MfaFactor_userId_status_idx" ON "MfaFactor"("userId", "status");

-- CreateIndex
CREATE INDEX "RoleAssignment_userId_roleCode_idx" ON "RoleAssignment"("userId", "roleCode");

-- CreateIndex
CREATE INDEX "ConsentRecord_userId_consentType_version_idx" ON "ConsentRecord"("userId", "consentType", "version");

-- CreateIndex
CREATE INDEX "KycCase_userId_status_idx" ON "KycCase"("userId", "status");

-- CreateIndex
CREATE INDEX "KycDocument_kycCaseId_docType_idx" ON "KycDocument"("kycCaseId", "docType");

-- CreateIndex
CREATE INDEX "KycDecision_kycCaseId_createdAt_idx" ON "KycDecision"("kycCaseId", "createdAt");

-- CreateIndex
CREATE INDEX "ScreeningResult_kycCaseId_screeningType_idx" ON "ScreeningResult"("kycCaseId", "screeningType");

-- CreateIndex
CREATE INDEX "PaymentMethod_userId_status_type_idx" ON "PaymentMethod"("userId", "status", "type");

-- CreateIndex
CREATE UNIQUE INDEX "BankAccount_paymentMethodId_key" ON "BankAccount"("paymentMethodId");

-- CreateIndex
CREATE INDEX "Wallet_userId_type_status_idx" ON "Wallet"("userId", "type", "status");

-- CreateIndex
CREATE INDEX "WalletWhitelistEntry_userId_status_idx" ON "WalletWhitelistEntry"("userId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "WalletWhitelistEntry_userId_chain_address_key" ON "WalletWhitelistEntry"("userId", "chain", "address");

-- CreateIndex
CREATE INDEX "PartnerOrganization_type_country_idx" ON "PartnerOrganization"("type", "country");

-- CreateIndex
CREATE UNIQUE INDEX "AdvisorProfile_userId_key" ON "AdvisorProfile"("userId");

-- CreateIndex
CREATE INDEX "AdvisorClientAssignment_clientUserId_status_idx" ON "AdvisorClientAssignment"("clientUserId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "AdvisorClientAssignment_advisorUserId_clientUserId_key" ON "AdvisorClientAssignment"("advisorUserId", "clientUserId");

-- CreateIndex
CREATE UNIQUE INDEX "AptitudeDefinition_slug_key" ON "AptitudeDefinition"("slug");

-- CreateIndex
CREATE INDEX "AptitudeDefinition_category_orderIndex_idx" ON "AptitudeDefinition"("category", "orderIndex");

-- CreateIndex
CREATE UNIQUE INDEX "AptivioProfile_userId_key" ON "AptivioProfile"("userId");

-- CreateIndex
CREATE INDEX "AssessmentRun_aptivioProfileId_status_createdAt_idx" ON "AssessmentRun"("aptivioProfileId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "AssessmentRun_userId_createdAt_idx" ON "AssessmentRun"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "AssessmentAptitudeScore_aptitudeDefinitionId_idx" ON "AssessmentAptitudeScore"("aptitudeDefinitionId");

-- CreateIndex
CREATE UNIQUE INDEX "AssessmentAptitudeScore_assessmentRunId_aptitudeDefinitionI_key" ON "AssessmentAptitudeScore"("assessmentRunId", "aptitudeDefinitionId");

-- CreateIndex
CREATE UNIQUE INDEX "AptivioIdentity_aptivioProfileId_key" ON "AptivioIdentity"("aptivioProfileId");

-- CreateIndex
CREATE UNIQUE INDEX "AptivioIdentity_passportNumber_key" ON "AptivioIdentity"("passportNumber");

-- CreateIndex
CREATE INDEX "AuditEvent_actorType_actorId_idx" ON "AuditEvent"("actorType", "actorId");

-- CreateIndex
CREATE INDEX "AuditEvent_resourceType_resourceId_idx" ON "AuditEvent"("resourceType", "resourceId");

-- CreateIndex
CREATE INDEX "AuditEvent_action_createdAt_idx" ON "AuditEvent"("action", "createdAt");

-- CreateIndex
CREATE INDEX "Agent_principalType_kind_status_idx" ON "Agent"("principalType", "kind", "status");

-- CreateIndex
CREATE UNIQUE INDEX "AgentKey_keyHash_key" ON "AgentKey"("keyHash");

-- CreateIndex
CREATE INDEX "AgentKey_agentId_credentialType_idx" ON "AgentKey"("agentId", "credentialType");

-- CreateIndex
CREATE INDEX "Kyc_status_idx" ON "Kyc"("status");

-- CreateIndex
CREATE INDEX "Order_userId_createdAt_idx" ON "Order"("userId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "User_phone_key" ON "User"("phone");

-- CreateIndex
CREATE INDEX "User_status_idx" ON "User"("status");

-- AddForeignKey
ALTER TABLE "Agent" ADD CONSTRAINT "Agent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AgentKey" ADD CONSTRAINT "AgentKey_agentId_fkey" FOREIGN KEY ("agentId") REFERENCES "Agent"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Mandate" ADD CONSTRAINT "Mandate_agentId_fkey" FOREIGN KEY ("agentId") REFERENCES "Agent"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MandateUsage" ADD CONSTRAINT "MandateUsage_mandateId_fkey" FOREIGN KEY ("mandateId") REFERENCES "Mandate"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Kyc" ADD CONSTRAINT "Kyc_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Balance" ADD CONSTRAINT "Balance_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserProfile" ADD CONSTRAINT "UserProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Session" ADD CONSTRAINT "Session_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OtpChallenge" ADD CONSTRAINT "OtpChallenge_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MfaFactor" ADD CONSTRAINT "MfaFactor_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RoleAssignment" ADD CONSTRAINT "RoleAssignment_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConsentRecord" ADD CONSTRAINT "ConsentRecord_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "KycCase" ADD CONSTRAINT "KycCase_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "KycDocument" ADD CONSTRAINT "KycDocument_kycCaseId_fkey" FOREIGN KEY ("kycCaseId") REFERENCES "KycCase"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "KycDecision" ADD CONSTRAINT "KycDecision_kycCaseId_fkey" FOREIGN KEY ("kycCaseId") REFERENCES "KycCase"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ScreeningResult" ADD CONSTRAINT "ScreeningResult_kycCaseId_fkey" FOREIGN KEY ("kycCaseId") REFERENCES "KycCase"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PaymentMethod" ADD CONSTRAINT "PaymentMethod_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BankAccount" ADD CONSTRAINT "BankAccount_paymentMethodId_fkey" FOREIGN KEY ("paymentMethodId") REFERENCES "PaymentMethod"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Wallet" ADD CONSTRAINT "Wallet_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WalletWhitelistEntry" ADD CONSTRAINT "WalletWhitelistEntry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdvisorProfile" ADD CONSTRAINT "AdvisorProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdvisorProfile" ADD CONSTRAINT "AdvisorProfile_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "PartnerOrganization"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdvisorClientAssignment" ADD CONSTRAINT "AdvisorClientAssignment_advisorUserId_fkey" FOREIGN KEY ("advisorUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdvisorClientAssignment" ADD CONSTRAINT "AdvisorClientAssignment_clientUserId_fkey" FOREIGN KEY ("clientUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AptivioProfile" ADD CONSTRAINT "AptivioProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AssessmentRun" ADD CONSTRAINT "AssessmentRun_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AssessmentRun" ADD CONSTRAINT "AssessmentRun_aptivioProfileId_fkey" FOREIGN KEY ("aptivioProfileId") REFERENCES "AptivioProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AssessmentAptitudeScore" ADD CONSTRAINT "AssessmentAptitudeScore_assessmentRunId_fkey" FOREIGN KEY ("assessmentRunId") REFERENCES "AssessmentRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AssessmentAptitudeScore" ADD CONSTRAINT "AssessmentAptitudeScore_aptitudeDefinitionId_fkey" FOREIGN KEY ("aptitudeDefinitionId") REFERENCES "AptitudeDefinition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AptivioIdentity" ADD CONSTRAINT "AptivioIdentity_aptivioProfileId_fkey" FOREIGN KEY ("aptivioProfileId") REFERENCES "AptivioProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;
