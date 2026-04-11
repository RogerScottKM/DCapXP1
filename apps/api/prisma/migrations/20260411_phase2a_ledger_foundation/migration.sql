DO $$ BEGIN
  CREATE TYPE "LedgerAccountOwnerType" AS ENUM ('SYSTEM', 'USER');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "LedgerAccountType" AS ENUM (
    'USER_AVAILABLE',
    'USER_HELD',
    'EXCHANGE_INVENTORY',
    'FEE_REVENUE',
    'TREASURY',
    'SUSPENSE'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "LedgerTransactionStatus" AS ENUM ('POSTED', 'VOIDED');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "LedgerPostingSide" AS ENUM ('DEBIT', 'CREDIT');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS "LedgerAccount" (
  "id" TEXT NOT NULL,
  "ownerType" "LedgerAccountOwnerType" NOT NULL,
  "ownerRef" TEXT NOT NULL,
  "assetCode" TEXT NOT NULL,
  "mode" "TradeMode" NOT NULL,
  "accountType" "LedgerAccountType" NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "LedgerAccount_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "LedgerTransaction" (
  "id" TEXT NOT NULL,
  "referenceType" TEXT,
  "referenceId" TEXT,
  "description" TEXT,
  "status" "LedgerTransactionStatus" NOT NULL DEFAULT 'POSTED',
  "metadata" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "LedgerTransaction_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "LedgerPosting" (
  "id" TEXT NOT NULL,
  "transactionId" TEXT NOT NULL,
  "accountId" TEXT NOT NULL,
  "assetCode" TEXT NOT NULL,
  "side" "LedgerPostingSide" NOT NULL,
  "amount" DECIMAL(30,10) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "LedgerPosting_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "LedgerPosting_transactionId_fkey" FOREIGN KEY ("transactionId") REFERENCES "LedgerTransaction"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "LedgerPosting_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "LedgerAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "LedgerAccount_ownerType_ownerRef_assetCode_mode_accountType_key"
  ON "LedgerAccount" ("ownerType", "ownerRef", "assetCode", "mode", "accountType");

CREATE INDEX IF NOT EXISTS "LedgerAccount_assetCode_mode_accountType_idx"
  ON "LedgerAccount" ("assetCode", "mode", "accountType");

CREATE INDEX IF NOT EXISTS "LedgerAccount_ownerType_ownerRef_mode_idx"
  ON "LedgerAccount" ("ownerType", "ownerRef", "mode");

CREATE INDEX IF NOT EXISTS "LedgerTransaction_referenceType_referenceId_idx"
  ON "LedgerTransaction" ("referenceType", "referenceId");

CREATE INDEX IF NOT EXISTS "LedgerTransaction_createdAt_idx"
  ON "LedgerTransaction" ("createdAt");

CREATE INDEX IF NOT EXISTS "LedgerPosting_transactionId_idx"
  ON "LedgerPosting" ("transactionId");

CREATE INDEX IF NOT EXISTS "LedgerPosting_accountId_idx"
  ON "LedgerPosting" ("accountId");

CREATE INDEX IF NOT EXISTS "LedgerPosting_assetCode_createdAt_idx"
  ON "LedgerPosting" ("assetCode", "createdAt");
