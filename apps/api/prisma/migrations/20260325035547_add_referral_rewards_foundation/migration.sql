-- CreateEnum
CREATE TYPE "ReferralCodeStatus" AS ENUM ('ACTIVE', 'DISABLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "ReferralAttributionStatus" AS ENUM ('PENDING', 'CONFIRMED', 'REJECTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "ReferralApplySource" AS ENUM ('LOGIN', 'ONBOARDING', 'INVITATION', 'REGISTER', 'ADMIN', 'IMPORT');

-- CreateEnum
CREATE TYPE "RewardUnitType" AS ENUM ('POINTS', 'CASH', 'TOKEN', 'PROFIT_SHARE', 'STOCK_OPTION');

-- CreateEnum
CREATE TYPE "RewardEntryType" AS ENUM ('ACCRUAL', 'ADJUSTMENT', 'REDEMPTION', 'REVERSAL');

-- CreateEnum
CREATE TYPE "RewardSourceType" AS ENUM ('REFERRAL_CODE_APPLIED', 'REFERRAL_SIGNUP', 'REFERRAL_CONTACT_VERIFIED', 'REFERRAL_KYC_APPROVED', 'REFERRAL_FIRST_FUNDING', 'REFERRAL_FIRST_TRADE', 'MANUAL_BONUS', 'CAMPAIGN_BONUS');

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "acquisitionSource" TEXT,
ADD COLUMN     "referredByCodeInput" TEXT;

-- CreateTable
CREATE TABLE "ReferralCode" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "ownerUserId" TEXT NOT NULL,
    "status" "ReferralCodeStatus" NOT NULL DEFAULT 'ACTIVE',
    "campaignKey" TEXT,
    "communityKey" TEXT,
    "regionKey" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ReferralCode_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ReferralAttribution" (
    "id" TEXT NOT NULL,
    "referredUserId" TEXT NOT NULL,
    "referralCodeId" TEXT NOT NULL,
    "referrerUserId" TEXT NOT NULL,
    "status" "ReferralAttributionStatus" NOT NULL DEFAULT 'PENDING',
    "applySource" "ReferralApplySource",
    "attributedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "confirmedAt" TIMESTAMP(3),
    "communityKey" TEXT,
    "regionKey" TEXT,
    "lineageSnapshot" JSONB,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ReferralAttribution_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RewardLedgerEntry" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "attributionId" TEXT,
    "unitType" "RewardUnitType" NOT NULL,
    "entryType" "RewardEntryType" NOT NULL,
    "sourceType" "RewardSourceType" NOT NULL,
    "amount" DECIMAL(18,4) NOT NULL,
    "currencyCode" TEXT,
    "description" TEXT,
    "effectiveAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RewardLedgerEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserRewardBalance" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "unitType" "RewardUnitType" NOT NULL,
    "balance" DECIMAL(18,4) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserRewardBalance_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ReferralCode_code_key" ON "ReferralCode"("code");

-- CreateIndex
CREATE INDEX "ReferralCode_ownerUserId_status_idx" ON "ReferralCode"("ownerUserId", "status");

-- CreateIndex
CREATE INDEX "ReferralCode_campaignKey_status_idx" ON "ReferralCode"("campaignKey", "status");

-- CreateIndex
CREATE INDEX "ReferralCode_communityKey_status_idx" ON "ReferralCode"("communityKey", "status");

-- CreateIndex
CREATE INDEX "ReferralCode_regionKey_status_idx" ON "ReferralCode"("regionKey", "status");

-- CreateIndex
CREATE UNIQUE INDEX "ReferralAttribution_referredUserId_key" ON "ReferralAttribution"("referredUserId");

-- CreateIndex
CREATE INDEX "ReferralAttribution_referrerUserId_status_idx" ON "ReferralAttribution"("referrerUserId", "status");

-- CreateIndex
CREATE INDEX "ReferralAttribution_referralCodeId_status_idx" ON "ReferralAttribution"("referralCodeId", "status");

-- CreateIndex
CREATE INDEX "ReferralAttribution_communityKey_status_idx" ON "ReferralAttribution"("communityKey", "status");

-- CreateIndex
CREATE INDEX "ReferralAttribution_regionKey_status_idx" ON "ReferralAttribution"("regionKey", "status");

-- CreateIndex
CREATE INDEX "RewardLedgerEntry_userId_unitType_effectiveAt_idx" ON "RewardLedgerEntry"("userId", "unitType", "effectiveAt");

-- CreateIndex
CREATE INDEX "RewardLedgerEntry_attributionId_sourceType_idx" ON "RewardLedgerEntry"("attributionId", "sourceType");

-- CreateIndex
CREATE UNIQUE INDEX "UserRewardBalance_userId_unitType_key" ON "UserRewardBalance"("userId", "unitType");

-- AddForeignKey
ALTER TABLE "ReferralCode" ADD CONSTRAINT "ReferralCode_ownerUserId_fkey" FOREIGN KEY ("ownerUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReferralAttribution" ADD CONSTRAINT "ReferralAttribution_referredUserId_fkey" FOREIGN KEY ("referredUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReferralAttribution" ADD CONSTRAINT "ReferralAttribution_referralCodeId_fkey" FOREIGN KEY ("referralCodeId") REFERENCES "ReferralCode"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReferralAttribution" ADD CONSTRAINT "ReferralAttribution_referrerUserId_fkey" FOREIGN KEY ("referrerUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RewardLedgerEntry" ADD CONSTRAINT "RewardLedgerEntry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RewardLedgerEntry" ADD CONSTRAINT "RewardLedgerEntry_attributionId_fkey" FOREIGN KEY ("attributionId") REFERENCES "ReferralAttribution"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserRewardBalance" ADD CONSTRAINT "UserRewardBalance_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
