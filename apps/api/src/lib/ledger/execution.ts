import { Decimal } from "@prisma/client/runtime/library";
import {
  OrderSide,
  type Order,
  Prisma,
  TradeMode,
  type PrismaClient,
} from "@prisma/client";

import { prisma } from "../prisma";
import { ensureUserLedgerAccounts } from "./accounts";
import { settleMatchedTrade } from "./order-lifecycle";
import { assertExecutedQtyWithinOrder, computeRemainingQty, deriveOrderStatus } from "./order-state";
import { reconcileTradeSettlement } from "./reconciliation";
import { postLedgerTransaction } from "./service";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;
type Decimalish = string | number | Decimal | Prisma.Decimal;

type ExecuteLimitOrderInput = {
  orderId: string | bigint;
  quoteFeeBps?: Decimalish;
};

type PriceImprovementReleaseInput = {
  tradeRef: string;
  orderId: string | bigint;
  userId: string;
  symbol: string;
  limitPrice: Decimalish;
  executionPrice: Decimalish;
  fillQty: Decimalish;
  mode: TradeMode;
};

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

function minDecimal(a: Decimal, b: Decimal): Decimal {
  return a.lessThanOrEqualTo(b) ? a : b;
}

export function isCrossingLimitOrder(
  takerSide: OrderSide,
  takerPrice: Decimalish,
  makerPrice: Decimalish,
): boolean {
  const taker = toDecimal(takerPrice);
  const maker = toDecimal(makerPrice);
  return takerSide === "BUY" ? maker.lessThanOrEqualTo(taker) : maker.greaterThanOrEqualTo(taker);
}

export function computeQuoteFeeAmount(grossQuote: Decimalish, quoteFeeBps: Decimalish = 0): Decimal {
  const gross = toDecimal(grossQuote);
  const bps = toDecimal(quoteFeeBps);
  if (gross.lessThanOrEqualTo(0) || bps.lessThanOrEqualTo(0)) {
    return new Decimal(0);
  }
  return gross.mul(bps).div(10_000);
}

export function computeBuyPriceImprovementReleaseAmount(
  limitPrice: Decimalish,
  executionPrice: Decimalish,
  fillQty: Decimalish,
): Decimal {
  const limit = toDecimal(limitPrice);
  const execution = toDecimal(executionPrice);
  const qty = toDecimal(fillQty);
  if (qty.lessThanOrEqualTo(0) || execution.greaterThanOrEqualTo(limit)) {
    return new Decimal(0);
  }
  return limit.minus(execution).mul(qty);
}

export async function getOrderExecutedQty(
  orderId: string | bigint,
  db: LedgerDbClient = prisma,
): Promise<Decimal> {
  const normalizedId = BigInt(String(orderId));
  const [buyAgg, sellAgg] = await Promise.all([
    db.trade.aggregate({ where: { buyOrderId: normalizedId }, _sum: { qty: true } }),
    db.trade.aggregate({ where: { sellOrderId: normalizedId }, _sum: { qty: true } }),
  ]);

  const buyQty = buyAgg._sum.qty ? new Decimal(buyAgg._sum.qty) : new Decimal(0);
  const sellQty = sellAgg._sum.qty ? new Decimal(sellAgg._sum.qty) : new Decimal(0);
  return buyQty.plus(sellQty);
}

export async function getOrderRemainingQty(
  order: Pick<Order, "id" | "qty">,
  db: LedgerDbClient = prisma,
): Promise<Decimal> {
  const executed = await getOrderExecutedQty(order.id, db);
  assertExecutedQtyWithinOrder(order.qty, executed);
  return computeRemainingQty(order.qty, executed);
}

export async function syncOrderStatusFromTrades(
  orderId: bigint | string,
  db: LedgerDbClient = prisma,
): Promise<Order> {
  const normalizedId = BigInt(String(orderId));
  const order = await db.order.findUniqueOrThrow({ where: { id: normalizedId } });
  const executed = await getOrderExecutedQty(order.id, db);
  assertExecutedQtyWithinOrder(order.qty, executed);

  return db.order.update({
    where: { id: order.id },
    data: {
      status: deriveOrderStatus(order.status, order.qty, executed) as Order["status"],
    },
  });
}

async function findExistingReference(referenceType: string, referenceId: string, db: LedgerDbClient) {
  return db.ledgerTransaction.findFirst({
    where: { referenceType, referenceId },
    include: { postings: true },
  });
}

export async function releaseBuyPriceImprovement(
  input: PriceImprovementReleaseInput,
  db: LedgerDbClient = prisma,
) {
  const releaseAmount = computeBuyPriceImprovementReleaseAmount(
    input.limitPrice,
    input.executionPrice,
    input.fillQty,
  );
  if (releaseAmount.lessThanOrEqualTo(0)) {
    return null;
  }

  const referenceType = "ORDER_EVENT";
  const referenceId = `${input.tradeRef}:BUY_PRICE_IMPROVEMENT:${String(input.orderId)}`;
  const existing = await findExistingReference(referenceType, referenceId, db);
  if (existing) {
    return existing;
  }

  const quoteAsset = input.symbol.split("-")[1] ?? input.symbol;
  const userQuoteAccounts = await ensureUserLedgerAccounts(
    {
      userId: input.userId,
      assetCode: quoteAsset,
      mode: input.mode,
    },
    db,
  );

  return postLedgerTransaction(
    {
      referenceType,
      referenceId,
      description: `Release quote price improvement for BUY order ${String(input.orderId)}`,
      metadata: {
        event: "ORDER_BUY_PRICE_IMPROVEMENT_RELEASE",
        tradeRef: input.tradeRef,
        orderId: String(input.orderId),
        symbol: input.symbol,
        userId: input.userId,
        mode: input.mode,
        releaseAmount: releaseAmount.toString(),
      },
      postings: [
        {
          accountId: userQuoteAccounts.held.id,
          assetCode: userQuoteAccounts.held.assetCode,
          side: "DEBIT",
          amount: releaseAmount,
        },
        {
          accountId: userQuoteAccounts.available.id,
          assetCode: userQuoteAccounts.available.assetCode,
          side: "CREDIT",
          amount: releaseAmount,
        },
      ],
    },
    db,
  );
}

async function getMatchingOrders(order: Order, db: LedgerDbClient): Promise<Order[]> {
  const oppositeSide = order.side === "BUY" ? "SELL" : "BUY";
  const candidates = await db.order.findMany({
    where: {
      symbol: order.symbol,
      mode: order.mode,
      status: "OPEN",
      side: oppositeSide,
      NOT: { id: order.id },
    },
    orderBy:
      order.side === "BUY"
        ? [{ price: "asc" }, { createdAt: "asc" }]
        : [{ price: "desc" }, { createdAt: "asc" }],
  });

  return candidates.filter((candidate) => isCrossingLimitOrder(order.side, order.price, candidate.price));
}

export async function executeLimitOrderAgainstBook(
  input: ExecuteLimitOrderInput,
  db: LedgerDbClient = prisma,
) {
  const orderId = BigInt(String(input.orderId));
  const takerOrder = await db.order.findUniqueOrThrow({ where: { id: orderId } });
  if (takerOrder.status !== "OPEN") {
    throw new Error("Only OPEN orders can be executed in the Phase 2D matching path.");
  }
  if (!takerOrder.price) {
    throw new Error("Only LIMIT orders with a price can be executed in the Phase 2D matching path.");
  }

  const matches = await getMatchingOrders(takerOrder, db);
  const fills: Array<Record<string, unknown>> = [];
  let remaining = await getOrderRemainingQty(takerOrder, db);

  for (const makerOrder of matches) {
    if (remaining.lessThanOrEqualTo(0)) {
      break;
    }

    const makerRemaining = await getOrderRemainingQty(makerOrder, db);
    if (makerRemaining.lessThanOrEqualTo(0)) {
      continue;
    }

    const fillQty = minDecimal(remaining, makerRemaining);
    const executionPrice = new Decimal(makerOrder.price);
    const grossQuote = fillQty.mul(executionPrice);
    const quoteFee = computeQuoteFeeAmount(grossQuote, input.quoteFeeBps ?? 0);

    const buyOrder = takerOrder.side === "BUY" ? takerOrder : makerOrder;
    const sellOrder = takerOrder.side === "SELL" ? takerOrder : makerOrder;

    const trade = await db.trade.create({
      data: {
        symbol: takerOrder.symbol,
        price: executionPrice,
        qty: fillQty,
        mode: takerOrder.mode,
        buyOrderId: buyOrder.id,
        sellOrderId: sellOrder.id,
      },
    });

    const ledgerSettlement = await settleMatchedTrade(
      {
        tradeRef: trade.id.toString(),
        buyOrderId: buyOrder.id,
        sellOrderId: sellOrder.id,
        symbol: takerOrder.symbol,
        qty: fillQty,
        price: executionPrice,
        mode: takerOrder.mode,
        quoteFee,
      },
      db,
    );

    const buyPriceImprovementRelease = await releaseBuyPriceImprovement(
      {
        tradeRef: trade.id.toString(),
        orderId: buyOrder.id,
        userId: buyOrder.userId,
        symbol: takerOrder.symbol,
        limitPrice: buyOrder.price,
        executionPrice,
        fillQty,
        mode: takerOrder.mode,
      },
      db,
    );

    const reconciliation = await reconcileTradeSettlement(trade.id, db);

    await syncOrderStatusFromTrades(buyOrder.id, db);
    await syncOrderStatusFromTrades(sellOrder.id, db);

    fills.push({
      trade,
      ledgerSettlement,
      reconciliation,
      buyPriceImprovementRelease,
    });

    remaining = remaining.minus(fillQty);
  }

  const refreshedOrder = await db.order.findUniqueOrThrow({ where: { id: takerOrder.id } });
  const refreshedRemaining = await getOrderRemainingQty(refreshedOrder, db);

  return {
    order: refreshedOrder,
    fills,
    remainingQty: refreshedRemaining.toString(),
  };
}

export async function reconcileOrderExecution(orderId: string | bigint, db: LedgerDbClient = prisma) {
  const normalizedId = BigInt(String(orderId));
  const order = await db.order.findUniqueOrThrow({ where: { id: normalizedId } });
  const trades = await db.trade.findMany({
    where: {
      OR: [{ buyOrderId: normalizedId }, { sellOrderId: normalizedId }],
    },
    orderBy: { createdAt: "asc" },
  });

  const ledgerReferenceIds = trades.map((trade) => `${trade.id}:FILL_SETTLEMENT`);
  const ledgerTransactions = ledgerReferenceIds.length
    ? await db.ledgerTransaction.findMany({
        where: {
          referenceType: "ORDER_EVENT",
          referenceId: { in: ledgerReferenceIds },
        },
      })
    : [];

  const executedQty = trades.reduce((acc, trade) => acc.plus(new Decimal(trade.qty)), new Decimal(0));
  assertExecutedQtyWithinOrder(order.qty, executedQty);
  const safeRemaining = computeRemainingQty(order.qty, executedQty);

  if (ledgerTransactions.length !== trades.length) {
    throw new Error("Trade to ledger transaction count mismatch for order reconciliation.");
  }

  const expectedStatus = deriveOrderStatus(order.status, order.qty, executedQty);
  if (order.status !== expectedStatus) {
    throw new Error(`Order status mismatch: expected ${expectedStatus}, got ${order.status}`);
  }

  return {
    orderId: String(order.id),
    status: order.status,
    expectedStatus,
    tradeCount: trades.length,
    ledgerTransactionCount: ledgerTransactions.length,
    executedQty: executedQty.toString(),
    remainingQty: safeRemaining.toString(),
  };
}
