-- Phase 3B: persistent idempotency keys for order placement and cancel requests.

CREATE TABLE IF NOT EXISTS "IdempotencyKey" (
  "id" TEXT NOT NULL,
  "ownerType" TEXT NOT NULL,
  "ownerId" TEXT NOT NULL,
  "scope" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  "requestHash" TEXT NOT NULL,
  "method" TEXT NOT NULL,
  "path" TEXT NOT NULL,
  "state" TEXT NOT NULL DEFAULT 'PENDING',
  "responseStatus" INTEGER,
  "responseBody" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "IdempotencyKey_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "IdempotencyKey_ownerType_ownerId_scope_key_key"
  ON "IdempotencyKey"("ownerType", "ownerId", "scope", "key");

CREATE INDEX IF NOT EXISTS "IdempotencyKey_scope_key_idx"
  ON "IdempotencyKey"("scope", "key");
