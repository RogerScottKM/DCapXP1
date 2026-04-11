#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import json

root = Path('.')

# 1) package.json: add a focused ledger test script if missing
pkg_path = root / 'apps/api/package.json'
pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault('scripts', {})
if 'test:ledger' not in scripts:
    scripts['test:ledger'] = 'vitest run test/ledger.posting.test.ts'
pkg_path.write_text(json.dumps(pkg, indent=2) + '\n')

# 2) schema.prisma: append ledger enums/models if missing
schema_path = root / 'apps/api/prisma/schema.prisma'
schema = schema_path.read_text()
if 'model LedgerAccount {' not in schema:
    block = '''

enum LedgerAccountOwnerType {
  SYSTEM
  USER
}

enum LedgerAccountType {
  USER_AVAILABLE
  USER_HELD
  EXCHANGE_INVENTORY
  FEE_REVENUE
  TREASURY
  SUSPENSE
}

enum LedgerTransactionStatus {
  POSTED
  VOIDED
}

enum LedgerPostingSide {
  DEBIT
  CREDIT
}

model LedgerAccount {
  id          String                 @id @default(cuid())
  ownerType   LedgerAccountOwnerType
  ownerRef    String
  assetCode   String
  mode        TradeMode
  accountType LedgerAccountType
  status      String                 @default("ACTIVE")
  createdAt   DateTime               @default(now())
  updatedAt   DateTime               @default(now()) @updatedAt
  postings    LedgerPosting[]

  @@unique([ownerType, ownerRef, assetCode, mode, accountType])
  @@index([assetCode, mode, accountType])
  @@index([ownerType, ownerRef, mode])
}

model LedgerTransaction {
  id            String                  @id @default(cuid())
  referenceType String?
  referenceId   String?
  description   String?
  status        LedgerTransactionStatus @default(POSTED)
  metadata      Json?
  createdAt     DateTime                @default(now())
  postings      LedgerPosting[]

  @@index([referenceType, referenceId])
  @@index([createdAt])
}

model LedgerPosting {
  id            String            @id @default(cuid())
  transactionId String
  accountId     String
  assetCode     String
  side          LedgerPostingSide
  amount        Decimal           @db.Decimal(30, 10)
  createdAt     DateTime          @default(now())
  transaction   LedgerTransaction @relation(fields: [transactionId], references: [id], onDelete: Cascade)
  account       LedgerAccount     @relation(fields: [accountId], references: [id], onDelete: Restrict)

  @@index([transactionId])
  @@index([accountId])
  @@index([assetCode, createdAt])
}
'''
    schema_path.write_text(schema.rstrip() + block + '\n')

# 3) migration
migration_dir = root / 'apps/api/prisma/migrations/20260411_phase2a_ledger_foundation'
migration_dir.mkdir(parents=True, exist_ok=True)
migration_sql = migration_dir / 'migration.sql'
migration_sql.write_text('''DO $$ BEGIN
  CREATE TYPE "LedgerAccountOwnerType" AS ENUM (\'SYSTEM\', \'USER\');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "LedgerAccountType" AS ENUM (
    \'USER_AVAILABLE\',
    \'USER_HELD\',
    \'EXCHANGE_INVENTORY\',
    \'FEE_REVENUE\',
    \'TREASURY\',
    \'SUSPENSE\'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "LedgerTransactionStatus" AS ENUM (\'POSTED\', \'VOIDED\');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "LedgerPostingSide" AS ENUM (\'DEBIT\', \'CREDIT\');
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
  "status" TEXT NOT NULL DEFAULT \'ACTIVE\',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "LedgerAccount_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "LedgerTransaction" (
  "id" TEXT NOT NULL,
  "referenceType" TEXT,
  "referenceId" TEXT,
  "description" TEXT,
  "status" "LedgerTransactionStatus" NOT NULL DEFAULT \'POSTED\',
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
''')

# 4) ledger helper files
ledger_dir = root / 'apps/api/src/lib/ledger'
ledger_dir.mkdir(parents=True, exist_ok=True)

(ledger_dir / 'posting.ts').write_text('''import { Decimal } from "@prisma/client/runtime/library";
import type { LedgerPostingSide } from "@prisma/client";

export type PostingSide = LedgerPostingSide | "DEBIT" | "CREDIT";

export type PostingInput = {
  accountId: string;
  assetCode: string;
  side: PostingSide;
  amount: string | number | Decimal;
};

export type NormalizedPosting = {
  accountId: string;
  assetCode: string;
  side: "DEBIT" | "CREDIT";
  amount: Decimal;
};

export function toDecimal(value: string | number | Decimal): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export function normalizePostings(postings: PostingInput[]): NormalizedPosting[] {
  return postings.map((posting) => {
    const accountId = String(posting.accountId ?? "").trim();
    const assetCode = String(posting.assetCode ?? "").trim().toUpperCase();
    const side = posting.side === "CREDIT" ? "CREDIT" : "DEBIT";
    const amount = toDecimal(posting.amount);

    if (!accountId) {
      throw new Error("Ledger posting accountId is required.");
    }
    if (!assetCode) {
      throw new Error("Ledger posting assetCode is required.");
    }
    if (amount.lte(0)) {
      throw new Error("Ledger posting amount must be greater than zero.");
    }

    return { accountId, assetCode, side, amount };
  });
}

export function assertBalancedPostings(postings: PostingInput[]): NormalizedPosting[] {
  if (postings.length < 2) {
    throw new Error("Ledger transaction must include at least two postings.");
  }

  const normalized = normalizePostings(postings);
  const grouped = new Map<string, { debit: Decimal; credit: Decimal }>();

  for (const posting of normalized) {
    const current = grouped.get(posting.assetCode) ?? {
      debit: new Decimal(0),
      credit: new Decimal(0),
    };

    if (posting.side === "DEBIT") {
      current.debit = current.debit.plus(posting.amount);
    } else {
      current.credit = current.credit.plus(posting.amount);
    }

    grouped.set(posting.assetCode, current);
  }

  for (const [assetCode, totals] of grouped.entries()) {
    if (!totals.debit.eq(totals.credit)) {
      throw new Error(`Ledger postings are not balanced for asset ${assetCode}.`);
    }
  }

  return normalized;
}

export function buildLedgerTransfer(params: {
  fromAccountId: string;
  toAccountId: string;
  assetCode: string;
  amount: string | number | Decimal;
}): PostingInput[] {
  const amount = toDecimal(params.amount);
  if (amount.lte(0)) {
    throw new Error("Ledger transfer amount must be greater than zero.");
  }

  return [
    {
      accountId: params.fromAccountId,
      assetCode: params.assetCode,
      side: "CREDIT",
      amount,
    },
    {
      accountId: params.toAccountId,
      assetCode: params.assetCode,
      side: "DEBIT",
      amount,
    },
  ];
}
''')

(ledger_dir / 'accounts.ts').write_text('''import {
  LedgerAccountOwnerType,
  LedgerAccountType,
  TradeMode,
  type Prisma,
  type PrismaClient,
} from "@prisma/client";

import { prisma } from "../prisma";

export const SYSTEM_LEDGER_OWNER_REF = "SYSTEM";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

type EnsureLedgerAccountInput = {
  ownerType: LedgerAccountOwnerType;
  ownerRef: string;
  assetCode: string;
  mode: TradeMode;
  accountType: LedgerAccountType;
};

export async function ensureLedgerAccount(
  input: EnsureLedgerAccountInput,
  db: LedgerDbClient = prisma,
) {
  const ownerRef = String(input.ownerRef ?? "").trim();
  const assetCode = String(input.assetCode ?? "").trim().toUpperCase();

  const existing = await db.ledgerAccount.findFirst({
    where: {
      ownerType: input.ownerType,
      ownerRef,
      assetCode,
      mode: input.mode,
      accountType: input.accountType,
    },
  });

  if (existing) {
    return existing;
  }

  return db.ledgerAccount.create({
    data: {
      ownerType: input.ownerType,
      ownerRef,
      assetCode,
      mode: input.mode,
      accountType: input.accountType,
      status: "ACTIVE",
    },
  });
}

export async function ensureUserLedgerAccounts(
  params: { userId: string; assetCode: string; mode: TradeMode },
  db: LedgerDbClient = prisma,
) {
  const ownerType = LedgerAccountOwnerType.USER;
  const ownerRef = params.userId;

  const [available, held] = await Promise.all([
    ensureLedgerAccount(
      {
        ownerType,
        ownerRef,
        assetCode: params.assetCode,
        mode: params.mode,
        accountType: LedgerAccountType.USER_AVAILABLE,
      },
      db,
    ),
    ensureLedgerAccount(
      {
        ownerType,
        ownerRef,
        assetCode: params.assetCode,
        mode: params.mode,
        accountType: LedgerAccountType.USER_HELD,
      },
      db,
    ),
  ]);

  return { available, held };
}

export async function ensureSystemLedgerAccounts(
  params: { assetCode: string; mode: TradeMode },
  db: LedgerDbClient = prisma,
) {
  const ownerType = LedgerAccountOwnerType.SYSTEM;
  const ownerRef = SYSTEM_LEDGER_OWNER_REF;

  const [inventory, feeRevenue, treasury, suspense] = await Promise.all([
    ensureLedgerAccount(
      {
        ownerType,
        ownerRef,
        assetCode: params.assetCode,
        mode: params.mode,
        accountType: LedgerAccountType.EXCHANGE_INVENTORY,
      },
      db,
    ),
    ensureLedgerAccount(
      {
        ownerType,
        ownerRef,
        assetCode: params.assetCode,
        mode: params.mode,
        accountType: LedgerAccountType.FEE_REVENUE,
      },
      db,
    ),
    ensureLedgerAccount(
      {
        ownerType,
        ownerRef,
        assetCode: params.assetCode,
        mode: params.mode,
        accountType: LedgerAccountType.TREASURY,
      },
      db,
    ),
    ensureLedgerAccount(
      {
        ownerType,
        ownerRef,
        assetCode: params.assetCode,
        mode: params.mode,
        accountType: LedgerAccountType.SUSPENSE,
      },
      db,
    ),
  ]);

  return { inventory, feeRevenue, treasury, suspense };
}
''')

(ledger_dir / 'service.ts').write_text('''import { Prisma, type PrismaClient } from "@prisma/client";

import { prisma } from "../prisma";
import { assertBalancedPostings, type PostingInput } from "./posting";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export type LedgerTransactionInput = {
  referenceType?: string;
  referenceId?: string;
  description?: string;
  metadata?: Prisma.InputJsonValue;
  postings: PostingInput[];
};

async function createPostedTransaction(
  db: LedgerDbClient,
  input: LedgerTransactionInput,
) {
  const postings = assertBalancedPostings(input.postings);

  const transaction = await db.ledgerTransaction.create({
    data: {
      referenceType: input.referenceType,
      referenceId: input.referenceId,
      description: input.description,
      metadata: input.metadata,
      status: "POSTED",
    },
  });

  await db.ledgerPosting.createMany({
    data: postings.map((posting) => ({
      transactionId: transaction.id,
      accountId: posting.accountId,
      assetCode: posting.assetCode,
      side: posting.side,
      amount: posting.amount.toString(),
    })),
  });

  return db.ledgerTransaction.findUniqueOrThrow({
    where: { id: transaction.id },
    include: { postings: true },
  });
}

export async function postLedgerTransaction(
  input: LedgerTransactionInput,
  db: LedgerDbClient = prisma,
) {
  if ("$transaction" in db) {
    return db.$transaction((tx) => createPostedTransaction(tx as Prisma.TransactionClient, input));
  }

  return createPostedTransaction(db, input);
}
''')

(ledger_dir / 'index.ts').write_text('''export * from "./posting";
export * from "./accounts";
export * from "./service";
''')

# 5) tests

test_dir = root / 'apps/api/test'
test_dir.mkdir(parents=True, exist_ok=True)
(test_dir / 'ledger.posting.test.ts').write_text('''import { describe, expect, it } from "vitest";

import { assertBalancedPostings, buildLedgerTransfer } from "../src/lib/ledger/posting";

describe("ledger posting invariants", () => {
  it("accepts balanced postings", () => {
    const postings = assertBalancedPostings([
      { accountId: "a1", assetCode: "USD", side: "DEBIT", amount: "100.00" },
      { accountId: "a2", assetCode: "USD", side: "CREDIT", amount: "100.00" },
    ]);

    expect(postings).toHaveLength(2);
    expect(postings[0].assetCode).toBe("USD");
  });

  it("rejects unbalanced postings", () => {
    expect(() =>
      assertBalancedPostings([
        { accountId: "a1", assetCode: "USD", side: "DEBIT", amount: "100.00" },
        { accountId: "a2", assetCode: "USD", side: "CREDIT", amount: "90.00" },
      ]),
    ).toThrow(/not balanced/i);
  });

  it("buildLedgerTransfer creates a balanced transfer pair", () => {
    const transfer = buildLedgerTransfer({
      fromAccountId: "held-usd",
      toAccountId: "available-usd",
      assetCode: "USD",
      amount: "25.5",
    });

    const normalized = assertBalancedPostings(transfer);
    expect(normalized).toHaveLength(2);
    expect(normalized[0].side).toBe("CREDIT");
    expect(normalized[1].side).toBe("DEBIT");
  });
});
''')

print('Patched package.json, schema.prisma, migration, ledger helpers, and ledger tests for Phase 2A.')
PY

echo 'Phase 2A patch applied.'
