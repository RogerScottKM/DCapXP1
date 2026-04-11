import { Decimal } from "@prisma/client/runtime/library";
import { Prisma, type PrismaClient } from "@prisma/client";

import { prisma } from "../prisma";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export type SettlementConsistencyInput = {
  trade: {
    id: bigint;
    symbol: string;
    qty: Decimal;
    price: Decimal;
    mode: string;
    buyOrderId: bigint;
    sellOrderId: bigint;
  };
  ledgerTransaction: {
    referenceType: string | null;
    referenceId: string | null;
    metadata: Prisma.JsonValue | null;
    postings?: Array<{ assetCode: string; amount: Decimal | string; side: string }>;
  };
};

function readMetadataObject(value: Prisma.JsonValue | null): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, unknown>;
}

function asString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  return String(value);
}

function assertDecimalEqual(actual: Decimal, expected: Decimal, label: string) {
  if (!actual.eq(expected)) {
    throw new Error(`${label} mismatch: expected ${expected.toString()}, got ${actual.toString()}`);
  }
}

export function assertTradeSettlementConsistency(input: SettlementConsistencyInput) {
  const metadata = readMetadataObject(input.ledgerTransaction.metadata);

  const expectedReferenceId = `${input.trade.id.toString()}:FILL_SETTLEMENT`;
  if (input.ledgerTransaction.referenceType !== "ORDER_EVENT") {
    throw new Error("Ledger transaction referenceType must be ORDER_EVENT for fills.");
  }
  if (input.ledgerTransaction.referenceId !== expectedReferenceId) {
    throw new Error("Ledger transaction referenceId does not match trade settlement reference.");
  }

  if (asString(metadata.tradeRef) !== input.trade.id.toString()) {
    throw new Error("Ledger transaction metadata.tradeRef does not match trade id.");
  }
  if (asString(metadata.buyOrderId) !== input.trade.buyOrderId.toString()) {
    throw new Error("Ledger transaction metadata.buyOrderId does not match.");
  }
  if (asString(metadata.sellOrderId) !== input.trade.sellOrderId.toString()) {
    throw new Error("Ledger transaction metadata.sellOrderId does not match.");
  }
  if (asString(metadata.symbol) !== input.trade.symbol) {
    throw new Error("Ledger transaction metadata.symbol does not match.");
  }
  if (asString(metadata.mode) !== input.trade.mode) {
    throw new Error("Ledger transaction metadata.mode does not match.");
  }

  const metadataQty = new Decimal(asString(metadata.qty) ?? "0");
  const metadataPrice = new Decimal(asString(metadata.price) ?? "0");
  assertDecimalEqual(metadataQty, new Decimal(input.trade.qty), "Trade quantity");
  assertDecimalEqual(metadataPrice, new Decimal(input.trade.price), "Trade price");

  const postings = input.ledgerTransaction.postings ?? [];
  if (postings.length < 4) {
    throw new Error("Ledger transaction must contain postings for fill settlement.");
  }

  return {
    ok: true as const,
    referenceId: expectedReferenceId,
    postingCount: postings.length,
  };
}

export async function reconcileTradeSettlement(
  tradeId: bigint | string,
  db: LedgerDbClient = prisma,
) {
  const resolvedTradeId = BigInt(String(tradeId));

  const trade = await db.trade.findUnique({
    where: { id: resolvedTradeId },
  });

  if (!trade) {
    throw new Error(`Trade ${resolvedTradeId.toString()} not found.`);
  }

  const ledgerTransaction = await db.ledgerTransaction.findFirst({
    where: {
      referenceType: "ORDER_EVENT",
      referenceId: `${trade.id.toString()}:FILL_SETTLEMENT`,
    },
    include: {
      postings: true,
    },
  });

  if (!ledgerTransaction) {
    throw new Error(`Ledger settlement not found for trade ${trade.id.toString()}.`);
  }

  return assertTradeSettlementConsistency({
    trade,
    ledgerTransaction,
  });
}
