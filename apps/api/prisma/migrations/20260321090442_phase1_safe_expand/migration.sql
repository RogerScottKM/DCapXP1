/*
  Warnings:

  - A unique constraint covering the columns `[channelCode]` on the table `PartnerOrganization` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "RoleScopeType" AS ENUM ('GLOBAL', 'PARTNER_ORG', 'CLIENT', 'ADVISOR_BOOK');

-- CreateEnum
CREATE TYPE "PartnerOrganizationStatus" AS ENUM ('PENDING', 'ACTIVE', 'INACTIVE');

-- CreateEnum
CREATE TYPE "PartnerReportScope" AS ENUM ('ORG_ONLY', 'ASSIGNED_ONLY', 'AGGREGATE');

-- CreateEnum
CREATE TYPE "InvitationType" AS ENUM ('CLIENT_ONBOARDING', 'ADVISOR_JOIN', 'PARTNER_OPERATOR_JOIN');

-- CreateEnum
CREATE TYPE "InvitationStatus" AS ENUM ('PENDING', 'ACCEPTED', 'EXPIRED', 'REVOKED');

-- CreateEnum
CREATE TYPE "AssessmentDefinitionStatus" AS ENUM ('DRAFT', 'ACTIVE', 'RETIRED');

-- CreateEnum
CREATE TYPE "AptivioBand" AS ENUM ('VERY_LOW', 'LOW', 'MODERATE', 'HIGH', 'VERY_HIGH');

-- CreateEnum
CREATE TYPE "AptivioSuitabilityStatus" AS ENUM ('INSUFFICIENT_DATA', 'PRELIMINARY_MATCH', 'NEEDS_ADVISER_REVIEW', 'CAUTION', 'NOT_ELIGIBLE');

-- CreateEnum
CREATE TYPE "AptivioEligibilityStatus" AS ENUM ('NOT_STARTED', 'PENDING', 'ELIGIBLE', 'REVIEW_REQUIRED', 'NOT_ELIGIBLE');

-- CreateEnum
CREATE TYPE "UploadStatus" AS ENUM ('UPLOADING', 'UPLOADED', 'SCANNING', 'AVAILABLE', 'QUARANTINED', 'REJECTED');

-- CreateEnum
CREATE TYPE "ConsentType" AS ENUM ('TERMS_OF_SERVICE', 'PRIVACY_POLICY', 'DATA_PROCESSING', 'ELECTRONIC_COMMUNICATION', 'APTIVIO_ASSESSMENT_AUTH', 'ADVISOR_DATA_SHARING_CONSENT');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "AssessmentRunStatus" ADD VALUE 'NOT_STARTED';
ALTER TYPE "AssessmentRunStatus" ADD VALUE 'IN_PROGRESS';
ALTER TYPE "AssessmentRunStatus" ADD VALUE 'SUBMITTED';
ALTER TYPE "AssessmentRunStatus" ADD VALUE 'SCORED';

-- AlterEnum
ALTER TYPE "RoleCode" ADD VALUE 'PARTNER_OPERATOR';

-- AlterTable
ALTER TABLE "AptivioProfile" ADD COLUMN     "aptivioIdEligibilityStatus" "AptivioEligibilityStatus",
ADD COLUMN     "assessedAt" TIMESTAMP(3),
ADD COLUMN     "behaviouralStabilityBand" "AptivioBand",
ADD COLUMN     "confidenceLevel" TEXT,
ADD COLUMN     "digitalTwinEligibilityStatus" "AptivioEligibilityStatus",
ADD COLUMN     "flagsJson" JSONB,
ADD COLUMN     "knowledgeExperienceBand" "AptivioBand",
ADD COLUMN     "latestAssessmentCode" TEXT,
ADD COLUMN     "latestAssessmentRunId" TEXT,
ADD COLUMN     "latestAssessmentVersion" INTEGER,
ADD COLUMN     "liquidityNeedBand" "AptivioBand",
ADD COLUMN     "lossCapacityBand" "AptivioBand",
ADD COLUMN     "overallReadinessScore" INTEGER,
ADD COLUMN     "promptsJson" JSONB,
ADD COLUMN     "riskBand" "AptivioBand",
ADD COLUMN     "suitabilityRationaleCodes" JSONB,
ADD COLUMN     "suitabilityStatus" "AptivioSuitabilityStatus",
ADD COLUMN     "timeHorizonBand" "AptivioBand";

-- AlterTable
ALTER TABLE "AssessmentRun" ADD COLUMN     "advisorSummaryJson" JSONB,
ADD COLUMN     "clientSummaryJson" JSONB,
ADD COLUMN     "definitionId" TEXT,
ADD COLUMN     "normalizedResultJson" JSONB,
ADD COLUMN     "scoredAt" TIMESTAMP(3),
ADD COLUMN     "submittedAt" TIMESTAMP(3),
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "ConsentRecord" ADD COLUMN     "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "revokedAt" TIMESTAMP(3),
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "KycDocument" ADD COLUMN     "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "reviewedAt" TIMESTAMP(3),
ADD COLUMN     "sizeBytes" INTEGER,
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "uploadStatus" "UploadStatus" NOT NULL DEFAULT 'UPLOADED';

-- AlterTable
ALTER TABLE "PartnerOrganization" ADD COLUMN     "brandingLogoUrl" TEXT,
ADD COLUMN     "brandingPrimaryColor" TEXT,
ADD COLUMN     "channelCode" TEXT,
ADD COLUMN     "contactEmail" TEXT,
ADD COLUMN     "contactName" TEXT,
ADD COLUMN     "contactPhone" TEXT,
ADD COLUMN     "inviteEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "onboardingEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "reportScope" "PartnerReportScope" NOT NULL DEFAULT 'ORG_ONLY',
ADD COLUMN     "status" "PartnerOrganizationStatus" NOT NULL DEFAULT 'PENDING';

-- AlterTable
ALTER TABLE "RoleAssignment" ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- CreateTable
CREATE TABLE "AssessmentDefinition" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "version" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "status" "AssessmentDefinitionStatus" NOT NULL DEFAULT 'DRAFT',
    "schemaJson" JSONB NOT NULL,
    "scoringConfigJson" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AssessmentDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "AssessmentDefinition_code_status_idx" ON "AssessmentDefinition"("code", "status");

-- CreateIndex
CREATE UNIQUE INDEX "AssessmentDefinition_code_version_key" ON "AssessmentDefinition"("code", "version");

-- CreateIndex
CREATE INDEX "AssessmentRun_definitionId_status_idx" ON "AssessmentRun"("definitionId", "status");

-- CreateIndex
CREATE INDEX "ConsentRecord_userId_consentType_revokedAt_idx" ON "ConsentRecord"("userId", "consentType", "revokedAt");

-- CreateIndex
CREATE INDEX "ConsentRecord_userId_acceptedAt_idx" ON "ConsentRecord"("userId", "acceptedAt");

-- CreateIndex
CREATE INDEX "KycDocument_kycCaseId_uploadStatus_idx" ON "KycDocument"("kycCaseId", "uploadStatus");

-- CreateIndex
CREATE UNIQUE INDEX "PartnerOrganization_channelCode_key" ON "PartnerOrganization"("channelCode");

-- CreateIndex
CREATE INDEX "PartnerOrganization_status_idx" ON "PartnerOrganization"("status");

-- CreateIndex
CREATE INDEX "RoleAssignment_roleCode_scopeType_scopeId_idx" ON "RoleAssignment"("roleCode", "scopeType", "scopeId");

-- AddForeignKey
ALTER TABLE "AssessmentRun" ADD CONSTRAINT "AssessmentRun_definitionId_fkey" FOREIGN KEY ("definitionId") REFERENCES "AssessmentDefinition"("id") ON DELETE SET NULL ON UPDATE CASCADE;
