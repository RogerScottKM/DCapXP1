-- CreateEnum
CREATE TYPE "VerificationStatus" AS ENUM ('PENDING', 'VERIFIED', 'EXPIRED', 'LOCKED', 'CANCELLED');

-- CreateTable
CREATE TABLE "VerificationChallenge" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "channel" "VerificationChannel" NOT NULL,
    "purpose" "VerificationPurpose" NOT NULL,
    "destinationMasked" TEXT NOT NULL,
    "destinationHash" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "maxAttempts" INTEGER NOT NULL DEFAULT 5,
    "status" "VerificationStatus" NOT NULL DEFAULT 'PENDING',
    "providerMessageId" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VerificationChallenge_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "NotificationDelivery" (
    "id" TEXT NOT NULL,
    "userId" TEXT,
    "channel" "VerificationChannel" NOT NULL,
    "templateKey" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "destinationMasked" TEXT NOT NULL,
    "providerMessageId" TEXT,
    "status" TEXT NOT NULL,
    "errorCode" TEXT,
    "errorMessage" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "NotificationDelivery_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "VerificationChallenge_userId_channel_purpose_status_idx" ON "VerificationChallenge"("userId", "channel", "purpose", "status");

-- CreateIndex
CREATE INDEX "VerificationChallenge_destinationHash_purpose_status_idx" ON "VerificationChallenge"("destinationHash", "purpose", "status");

-- CreateIndex
CREATE INDEX "NotificationDelivery_userId_channel_templateKey_status_idx" ON "NotificationDelivery"("userId", "channel", "templateKey", "status");

-- AddForeignKey
ALTER TABLE "VerificationChallenge" ADD CONSTRAINT "VerificationChallenge_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NotificationDelivery" ADD CONSTRAINT "NotificationDelivery_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
