import {
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
