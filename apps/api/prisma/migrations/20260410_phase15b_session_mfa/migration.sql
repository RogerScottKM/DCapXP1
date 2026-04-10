ALTER TABLE "Session" ADD COLUMN IF NOT EXISTS "mfaMethod" TEXT;
ALTER TABLE "Session" ADD COLUMN IF NOT EXISTS "mfaVerifiedAt" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "Session_userId_mfaVerifiedAt_idx"
  ON "Session" ("userId", "mfaVerifiedAt");
