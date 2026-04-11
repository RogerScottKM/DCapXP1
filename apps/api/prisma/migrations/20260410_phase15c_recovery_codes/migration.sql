CREATE TABLE IF NOT EXISTS "MfaRecoveryCode" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "codeHash" TEXT NOT NULL,
  "consumedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MfaRecoveryCode_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "MfaRecoveryCode_codeHash_key"
  ON "MfaRecoveryCode" ("codeHash");

CREATE INDEX IF NOT EXISTS "MfaRecoveryCode_userId_consumedAt_idx"
  ON "MfaRecoveryCode" ("userId", "consumedAt");
