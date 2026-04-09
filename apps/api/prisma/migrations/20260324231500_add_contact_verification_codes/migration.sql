-- CreateEnum
CREATE TYPE "VerificationChannel" AS ENUM ('EMAIL', 'SMS');

-- CreateEnum
CREATE TYPE "VerificationPurpose" AS ENUM ('CONTACT_VERIFICATION');

-- CreateTable
CREATE TABLE "VerificationCode" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "channel" "VerificationChannel" NOT NULL,
    "purpose" "VerificationPurpose" NOT NULL,
    "destination" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "VerificationCode_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "VerificationCode_userId_purpose_channel_expiresAt_idx" ON "VerificationCode"("userId", "purpose", "channel", "expiresAt");

-- CreateIndex
CREATE INDEX "VerificationCode_destination_purpose_channel_expiresAt_idx" ON "VerificationCode"("destination", "purpose", "channel", "expiresAt");

-- AddForeignKey
ALTER TABLE "VerificationCode" ADD CONSTRAINT "VerificationCode_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
