import { Decimal } from "@prisma/client/runtime/library";
import { Prisma, TradeMode, OrderSide, OrderStatus, type PrismaClient } from "@prisma/client";

import { prisma } from "../prisma";
import { ensureSystemLedgerAccounts, ensureUserLedgerAccounts } from "./accounts";
import { postLedgerTransaction } from "./service";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

type OrderPlacementInput = {
  orderId: string | bigint;
  userId: string;
  symbol: string;
  side: OrderSide;
  qty: string | number | Decimal;
  price: string | number | Decimal;
  mode: TradeMode;
};

type OrderReleaseInput = {
  orderId: string | bigint;
  userId: string;
  symbol: string;
  side: OrderSide;
  qty: string | number | Decimal;
  price: string | number | Decimal;
  mode: TradeMode;
  reason?: "CANCEL" | "RELEASE";
};

type OrderFillInput = {
  tradeRef: string;
  buyOrderId: string | bigint;
  sellOrderId: string | bigint;
  symbol: string;
  qty: string | number | Decimal;
  price: string | number | Decimal;
  mode: TradeMode;
  quoteFee?: string | number | Decimal;
};

function toDecimal(value: string | number | Decimal): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

async function findMarket(symbol: string, db: LedgerDbClient) {
  const market = await db.market.findUnique({ where: { symbol } });
  if (!market) {
    throw new Error(`Market not found for symbol ${symbol}`);
  }
  return market;
}

async function getLedgerBalance(accountId: string, db: LedgerDbClient): Promise<Decimal> {
  const postings = await db.ledgerPosting.findMany({
    where: { accountId },
    select: { side: true, amount: true },
  });

  return postings.reduce((acc, posting) => {
    const amount = new Decimal(posting.amount);
    return posting.side === "DEBIT" ? acc.minus(amount) : acc.plus(amount);
  }, new Decimal(0));
}

async function assertAccountHasBalance(accountId: string, required: Decimal, db: LedgerDbClient, label: string) {
  const balance = await getLedgerBalance(accountId, db);
  if (balance.lt(required)) {
    throw new Error(`${label} balance is insufficient for ledger movement.`);
  }
}

async function findExistingReference(referenceType: string, referenceId: string, db: LedgerDbClient) {
  return db.ledgerTransaction.findFirst({
    where: { referenceType, referenceId },
    include: { postings: true },
  });
}

export async function reserveOrderOnPlacement(input: OrderPlacementInput, db: LedgerDbClient = prisma) {
  const referenceType = "ORDER_EVENT";
  const referenceId = `${String(input.orderId)}:PLACE_HOLD`;
  const existing = await findExistingReference(referenceType, referenceId, db);
  if (existing) {
    return existing;
  }

  const market = await findMarket(input.symbol, db);
  const qty = toDecimal(input.qty);
  const price = toDecimal(input.price);

  if (qty.lte(0) || price.lte(0)) {
    throw new Error("Order quantity and price must be greater than zero.");
  }

  const assetCode = input.side === "BUY" ? market.quoteAsset : market.baseAsset;
  const holdAmount = input.side === "BUY" ? qty.mul(price) : qty;
  const userAccounts = await ensureUserLedgerAccounts({ userId: input.userId, assetCode, mode: input.mode }, db);

  await assertAccountHasBalance(userAccounts.available.id, holdAmount, db, "Available");

  return postLedgerTransaction({
    referenceType,
    referenceId,
    description: `Reserve ${assetCode} for ${input.side} order ${String(input.orderId)}`,
    metadata: {
      event: "ORDER_PLACE_HOLD",
      orderId: String(input.orderId),
      symbol: input.symbol,
      side: input.side,
      userId: input.userId,
      mode: input.mode,
      holdAsset: assetCode,
      holdAmount: holdAmount.toString(),
    },
    postings: [
      { accountId: userAccounts.available.id, assetCode, side: "DEBIT", amount: holdAmount },
      { accountId: userAccounts.held.id, assetCode, side: "CREDIT", amount: holdAmount },
    ],
  }, db);
}

export async function releaseOrderOnCancel(input: OrderReleaseInput, db: LedgerDbClient = prisma) {
  const referenceType = "ORDER_EVENT";
  const referenceId = `${String(input.orderId)}:${input.reason ?? "CANCEL"}_RELEASE`;
  const existing = await findExistingReference(referenceType, referenceId, db);
  if (existing) {
    return existing;
  }

  const market = await findMarket(input.symbol, db);
  const qty = toDecimal(input.qty);
  const price = toDecimal(input.price);
  const assetCode = input.side === "BUY" ? market.quoteAsset : market.baseAsset;
  const releaseAmount = input.side === "BUY" ? qty.mul(price) : qty;
  const userAccounts = await ensureUserLedgerAccounts({ userId: input.userId, assetCode, mode: input.mode }, db);

  await assertAccountHasBalance(userAccounts.held.id, releaseAmount, db, "Held");

  return postLedgerTransaction({
    referenceType,
    referenceId,
    description: `Release ${assetCode} hold for order ${String(input.orderId)}`,
    metadata: {
      event: "ORDER_CANCEL_RELEASE",
      orderId: String(input.orderId),
      symbol: input.symbol,
      side: input.side,
      userId: input.userId,
      mode: input.mode,
      releaseAsset: assetCode,
      releaseAmount: releaseAmount.toString(),
      reason: input.reason ?? "CANCEL",
    },
    postings: [
      { accountId: userAccounts.held.id, assetCode, side: "DEBIT", amount: releaseAmount },
      { accountId: userAccounts.available.id, assetCode, side: "CREDIT", amount: releaseAmount },
    ],
  }, db);
}

export async function settleMatchedTrade(input: OrderFillInput, db: LedgerDbClient = prisma) {
  const referenceType = "ORDER_EVENT";
  const referenceId = `${input.tradeRef}:FILL_SETTLEMENT`;
  const existing = await findExistingReference(referenceType, referenceId, db);
  if (existing) {
    return existing;
  }

  const market = await findMarket(input.symbol, db);
  const buyOrder = await db.order.findUnique({ where: { id: BigInt(String(input.buyOrderId)) } });
  const sellOrder = await db.order.findUnique({ where: { id: BigInt(String(input.sellOrderId)) } });

  if (!buyOrder || !sellOrder) {
    throw new Error("Both buy and sell orders are required for fill settlement.");
  }

  const qty = toDecimal(input.qty);
  const price = toDecimal(input.price);
  const grossQuote = qty.mul(price);
  const quoteFee = toDecimal(input.quoteFee ?? 0);
  if (quoteFee.lt(0)) {
    throw new Error("quoteFee cannot be negative.");
  }
  if (quoteFee.greaterThan(grossQuote)) {
    throw new Error("quoteFee cannot exceed gross quote amount.");
  }

  const buyerBase = await ensureUserLedgerAccounts({ userId: buyOrder.userId, assetCode: market.baseAsset, mode: input.mode }, db);
  const buyerQuote = await ensureUserLedgerAccounts({ userId: buyOrder.userId, assetCode: market.quoteAsset, mode: input.mode }, db);
  const sellerBase = await ensureUserLedgerAccounts({ userId: sellOrder.userId, assetCode: market.baseAsset, mode: input.mode }, db);
  const sellerQuote = await ensureUserLedgerAccounts({ userId: sellOrder.userId, assetCode: market.quoteAsset, mode: input.mode }, db);
  const quoteSystem = await ensureSystemLedgerAccounts({ assetCode: market.quoteAsset, mode: input.mode }, db);

  await assertAccountHasBalance(buyerQuote.held.id, grossQuote, db, "Buyer held quote");
  await assertAccountHasBalance(sellerBase.held.id, qty, db, "Seller held base");

  return postLedgerTransaction({
    referenceType,
    referenceId,
    description: `Settle matched trade ${input.tradeRef}`,
    metadata: {
      event: "ORDER_FILL_SETTLEMENT",
      tradeRef: input.tradeRef,
      buyOrderId: String(input.buyOrderId),
      sellOrderId: String(input.sellOrderId),
      symbol: input.symbol,
      qty: qty.toString(),
      price: price.toString(),
      grossQuote: grossQuote.toString(),
      quoteFee: quoteFee.toString(),
      mode: input.mode,
    },
    postings: [
      { accountId: buyerQuote.held.id, assetCode: market.quoteAsset, side: "DEBIT", amount: grossQuote },
      { accountId: sellerQuote.available.id, assetCode: market.quoteAsset, side: "CREDIT", amount: grossQuote.minus(quoteFee) },
      ...(quoteFee.gt(0)
        ? [{ accountId: quoteSystem.feeRevenue.id, assetCode: market.quoteAsset, side: "CREDIT" as const, amount: quoteFee }]
        : []),
      { accountId: sellerBase.held.id, assetCode: market.baseAsset, side: "DEBIT", amount: qty },
      { accountId: buyerBase.available.id, assetCode: market.baseAsset, side: "CREDIT", amount: qty },
    ],
  }, db);
}
