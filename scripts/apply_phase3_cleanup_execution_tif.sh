#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
exec_path = root / "apps/api/src/lib/ledger/execution.ts"
test_path = root / "apps/api/test/ledger.execution.phase3-cleanup.test.ts"

for p in [pkg_path, exec_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:ledger:execution-cleanup"] = "vitest run test/ledger.execution.phase3-cleanup.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

execution_ts = dedent("""\
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
import { releaseOrderOnCancel, settleMatchedTrade } from "./order-lifecycle";
import {
  assertExecutedQtyWithinOrder,
  assertValidTransition,
  canReceiveFills,
  computeRemainingQty,
  deriveOrderStatus,
  ORDER_STATUS,
} from "./order-state";
import {
  assertFokCanFullyFill,
  assertPostOnlyWouldRest,
  deriveTifRestingAction,
  normalizeTimeInForce,
  ORDER_TIF,
} from "./time-in-force";
import { reconcileTradeSettlement } from "./reconciliation";
import { postLedgerTransaction } from "./service";
import { buildMakerOrderByForTaker } from "./matching-priority";
import { computeBuyHeldQuoteRelease, assertCumulativeFillWithinOrder } from "./hold-release";

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

  const nextStatus = deriveOrderStatus(order.status, order.qty, executed);
  assertValidTransition(order.status, nextStatus);

  return db.order.update({
    where: { id: order.id },
    data: {
      status: nextStatus as Order["status"],
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
      status: { in: [ORDER_STATUS.OPEN, ORDER_STATUS.PARTIALLY_FILLED] },
      side: oppositeSide,
      NOT: { id: order.id },
    },
    orderBy: buildMakerOrderByForTaker(order.side),
  });

  return candidates.filter((candidate) => isCrossingLimitOrder(order.side, order.price, candidate.price));
}

export async function executeLimitOrderAgainstBook(
  input: ExecuteLimitOrderInput,
  db: LedgerDbClient = prisma,
) {
  const orderId = BigInt(String(input.orderId));
  const takerOrder = await db.order.findUniqueOrThrow({ where: { id: orderId } });

  if (!canReceiveFills(takerOrder.status)) {
    throw new Error(
      `Order ${takerOrder.id} cannot receive fills in status ${takerOrder.status}.`,
    );
  }
  if (!takerOrder.price) {
    throw new Error("Only LIMIT orders with a price can be executed.");
  }

  const tif = normalizeTimeInForce((takerOrder as any).timeInForce);
  const matches = await getMatchingOrders(takerOrder, db);

  if (tif === ORDER_TIF.POST_ONLY && matches.length > 0) {
    assertPostOnlyWouldRest(
      takerOrder.side,
      takerOrder.price,
      matches[0]?.price ?? null,
    );
  }

  if (tif === ORDER_TIF.FOK) {
    let fillableLiquidity = new Decimal(0);
    for (const m of matches) {
      const freshMaker = await db.order.findUnique({ where: { id: m.id } });
      if (!freshMaker || !canReceiveFills(freshMaker.status)) {
        continue;
      }
      const mRemaining = await getOrderRemainingQty(freshMaker, db);
      fillableLiquidity = fillableLiquidity.plus(mRemaining);
    }
    assertFokCanFullyFill(takerOrder.qty, fillableLiquidity);
  }

  const fills: Array<Record<string, unknown>> = [];
  let remaining = await getOrderRemainingQty(takerOrder, db);

  for (const makerOrder of matches) {
    if (remaining.lessThanOrEqualTo(0)) {
      break;
    }

    const freshMaker = await db.order.findUnique({ where: { id: makerOrder.id } });
    if (!freshMaker || !canReceiveFills(freshMaker.status)) {
      continue;
    }

    const makerRemaining = await getOrderRemainingQty(freshMaker, db);
    if (makerRemaining.lessThanOrEqualTo(0)) {
      continue;
    }

    const fillQty = minDecimal(remaining, makerRemaining);
    const executionPrice = new Decimal(freshMaker.price);
    const grossQuote = fillQty.mul(executionPrice);
    const quoteFee = computeQuoteFeeAmount(grossQuote, input.quoteFeeBps ?? 0);

    const buyOrder = takerOrder.side === "BUY" ? takerOrder : freshMaker;
    const sellOrder = takerOrder.side === "SELL" ? takerOrder : freshMaker;

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

  const executed = await getOrderExecutedQty(takerOrder.id, db);
  const tifAction = deriveTifRestingAction(tif, executed, takerOrder.qty);

  if (tifAction === "CANCEL_REMAINDER" && remaining.greaterThan(0)) {
    await releaseOrderOnCancel(
      {
        orderId: takerOrder.id,
        userId: takerOrder.userId,
        symbol: takerOrder.symbol,
        side: takerOrder.side,
        qty: remaining,
        price: takerOrder.price,
        mode: takerOrder.mode,
        reason: "CANCEL",
      },
      db,
    );

    assertValidTransition(ORDER_STATUS.OPEN, ORDER_STATUS.CANCELLED);
    await db.order.update({
      where: { id: takerOrder.id },
      data: { status: ORDER_STATUS.CANCELLED as Order["status"] },
    });
  }

  const refreshedOrder = await db.order.findUniqueOrThrow({ where: { id: takerOrder.id } });
  const refreshedRemaining = await getOrderRemainingQty(refreshedOrder, db);

  return {
    order: refreshedOrder,
    fills,
    remainingQty: refreshedRemaining.toString(),
    tifAction,
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

function toDecimalExecution(value: string | number | Decimal): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export async function releaseResidualHoldAfterExecution(params: {
  orderId: bigint;
  userId: string;
  symbol: string;
  side: "BUY" | "SELL";
  mode: TradeMode;
  orderQty: string | number | Decimal;
  limitPrice: string | number | Decimal;
  cumulativeFilledQty: string | number | Decimal;
  weightedExecutedQuote?: string | number | Decimal;
}, db: LedgerDbClient = prisma) {
  if (params.side !== "BUY") {
    return null;
  }

  const releaseAmount = computeBuyHeldQuoteRelease({
    orderQty: params.orderQty,
    limitPrice: params.limitPrice,
    cumulativeFilledQty: params.cumulativeFilledQty,
    weightedExecutedQuote: params.weightedExecutedQuote ?? "0",
  });

  if (releaseAmount.lessThanOrEqualTo(0)) {
    return null;
  }

  const referenceType = "ORDER_RELEASE";
  const referenceId = `${params.orderId}:FINAL_RESIDUAL_RELEASE`;

  const existing = await findExistingReference(referenceType, referenceId, db);
  if (existing) {
    return existing;
  }

  const quoteAsset = params.symbol.split("-")[1] ?? "USD";
  const userQuoteAccounts = await ensureUserLedgerAccounts(
    {
      userId: params.userId,
      assetCode: quoteAsset,
      mode: params.mode,
    },
    db,
  );

  return postLedgerTransaction(
    {
      referenceType,
      referenceId,
      description: "Release unused held quote after final buy execution",
      metadata: {
        orderId: params.orderId.toString(),
        symbol: params.symbol,
        side: params.side,
        reason: "FINAL_RESIDUAL_RELEASE",
        cumulativeFilledQty: String(params.cumulativeFilledQty),
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

export async function reconcileCumulativeFills(
  orderId: bigint,
  db: LedgerDbClient = prisma,
) {
  const order = await db.order.findUnique({ where: { id: orderId } });
  if (!order) {
    throw new Error("Order not found for cumulative fill reconciliation.");
  }

  const aggregate = await db.trade.aggregate({
    _sum: { qty: true },
    where: {
      OR: [{ buyOrderId: orderId }, { sellOrderId: orderId }],
    },
  });

  const cumulativeFilledQty = aggregate._sum.qty ?? new Decimal(0);
  assertCumulativeFillWithinOrder(order.qty, cumulativeFilledQty);

  const rawRemaining = toDecimalExecution(order.qty).sub(
    toDecimalExecution(cumulativeFilledQty),
  );
  const remainingQty = rawRemaining.lessThan(0) ? new Decimal(0) : rawRemaining;

  return {
    orderId: order.id.toString(),
    orderQty: toDecimalExecution(order.qty).toString(),
    cumulativeFilledQty: toDecimalExecution(cumulativeFilledQty).toString(),
    remainingQty: remainingQty.toString(),
  };
}
""")
exec_path.write_text(execution_ts)

test_ts = dedent("""\
import { beforeEach, describe, expect, it, vi } from "vitest";
import { Decimal } from "@prisma/client/runtime/library";

const {
  prismaMock,
  ensureUserLedgerAccounts,
  postLedgerTransaction,
  settleMatchedTrade,
  releaseOrderOnCancel,
  reconcileTradeSettlement,
} = vi.hoisted(() => ({
  prismaMock: {
    order: {
      findUniqueOrThrow: vi.fn(),
      findUnique: vi.fn(),
      findMany: vi.fn(),
      update: vi.fn(),
    },
    trade: {
      aggregate: vi.fn(),
      create: vi.fn(),
      findMany: vi.fn(),
    },
    ledgerTransaction: {
      findFirst: vi.fn(),
      findMany: vi.fn(),
    },
  },
  ensureUserLedgerAccounts: vi.fn(),
  postLedgerTransaction: vi.fn(),
  settleMatchedTrade: vi.fn(),
  releaseOrderOnCancel: vi.fn(),
  reconcileTradeSettlement: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/ledger/accounts", () => ({ ensureUserLedgerAccounts }));
vi.mock("../src/lib/ledger/service", () => ({ postLedgerTransaction }));
vi.mock("../src/lib/ledger/order-lifecycle", () => ({
  settleMatchedTrade,
  releaseOrderOnCancel,
}));
vi.mock("../src/lib/ledger/reconciliation", async () => {
  const actual = await vi.importActual("../src/lib/ledger/reconciliation");
  return {
    ...actual,
    reconcileTradeSettlement,
  };
});

import {
  executeLimitOrderAgainstBook,
  syncOrderStatusFromTrades,
} from "../src/lib/ledger/execution";
import { ORDER_STATUS } from "../src/lib/ledger/order-state";

function mkOrder(overrides: any = {}) {
  return {
    id: 1n,
    userId: "user-1",
    symbol: "BTC-USD",
    side: "BUY",
    price: new Decimal("100"),
    qty: new Decimal("10"),
    status: ORDER_STATUS.OPEN,
    mode: "PAPER",
    timeInForce: "GTC",
    createdAt: new Date("2026-01-01T00:00:00Z"),
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  ensureUserLedgerAccounts.mockResolvedValue({
    available: { id: "acct-available", assetCode: "USD" },
    held: { id: "acct-held", assetCode: "USD" },
  });
  postLedgerTransaction.mockResolvedValue({ id: "ltx-1" });
  settleMatchedTrade.mockResolvedValue({ id: "ltx-settle" });
  releaseOrderOnCancel.mockResolvedValue({ id: "ltx-release" });
  reconcileTradeSettlement.mockResolvedValue({ ok: true });
  prismaMock.ledgerTransaction.findFirst.mockResolvedValue(null);
  prismaMock.ledgerTransaction.findMany.mockResolvedValue([]);
  prismaMock.trade.findMany.mockResolvedValue([]);
});

describe("phase 3 execution cleanup", () => {
  it("allows a PARTIALLY_FILLED taker to re-enter matching", async () => {
    const taker = mkOrder({ id: 100n, status: ORDER_STATUS.PARTIALLY_FILLED, qty: new Decimal("10") });

    prismaMock.order.findUniqueOrThrow
      .mockResolvedValueOnce(taker)
      .mockResolvedValueOnce(taker);
    prismaMock.order.findMany.mockResolvedValue([]);
    prismaMock.trade.aggregate
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("4") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("4") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } });

    const result = await executeLimitOrderAgainstBook({ orderId: taker.id });

    expect(result.fills).toHaveLength(0);
    expect(result.remainingQty).toBe("6");
  });

  it("skips a maker that turned CANCELLED after initial candidate selection", async () => {
    const taker = mkOrder({ id: 100n, status: ORDER_STATUS.OPEN, qty: new Decimal("10") });
    const staleMaker = mkOrder({
      id: 200n,
      userId: "user-2",
      side: "SELL",
      qty: new Decimal("4"),
      price: new Decimal("95"),
      status: ORDER_STATUS.OPEN,
    });

    prismaMock.order.findUniqueOrThrow
      .mockResolvedValueOnce(taker)
      .mockResolvedValueOnce(taker);
    prismaMock.order.findMany.mockResolvedValue([staleMaker]);
    prismaMock.order.findUnique.mockResolvedValueOnce({
      ...staleMaker,
      status: ORDER_STATUS.CANCELLED,
    });
    prismaMock.trade.aggregate
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } });

    const result = await executeLimitOrderAgainstBook({ orderId: taker.id });

    expect(result.fills).toHaveLength(0);
    expect(prismaMock.trade.create).not.toHaveBeenCalled();
  });

  it("cancels IOC remainder through releaseOrderOnCancel and marks the order CANCELLED", async () => {
    const taker = mkOrder({
      id: 100n,
      status: ORDER_STATUS.OPEN,
      qty: new Decimal("10"),
      timeInForce: "IOC",
    });
    const maker = mkOrder({
      id: 200n,
      userId: "user-2",
      side: "SELL",
      qty: new Decimal("4"),
      price: new Decimal("95"),
      status: ORDER_STATUS.OPEN,
    });

    prismaMock.order.findUniqueOrThrow
      .mockResolvedValueOnce(taker)
      .mockResolvedValueOnce({ ...taker, status: ORDER_STATUS.PARTIALLY_FILLED })
      .mockResolvedValueOnce({ ...taker, status: ORDER_STATUS.CANCELLED });

    prismaMock.order.findMany.mockResolvedValue([maker]);
    prismaMock.order.findUnique
      .mockResolvedValueOnce(maker)
      .mockResolvedValueOnce({ ...maker, status: ORDER_STATUS.FILLED });

    prismaMock.trade.aggregate
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("4") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("4") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("4") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("4") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } });

    prismaMock.trade.create.mockResolvedValue({
      id: 500n,
      symbol: "BTC-USD",
      qty: new Decimal("4"),
      price: new Decimal("95"),
      buyOrderId: taker.id,
      sellOrderId: maker.id,
      mode: "PAPER",
    });

    prismaMock.order.update.mockImplementation(async ({ data }: any) => ({ ...taker, ...data }));

    const result = await executeLimitOrderAgainstBook({ orderId: taker.id });

    expect(releaseOrderOnCancel).toHaveBeenCalledTimes(1);
    expect(prismaMock.order.update).toHaveBeenCalledWith({
      where: { id: taker.id },
      data: { status: ORDER_STATUS.CANCELLED },
    });
    expect(result.tifAction).toBe("CANCEL_REMAINDER");
  });

  it("syncOrderStatusFromTrades preserves FILLED as a terminal state", async () => {
    const order = mkOrder({ qty: new Decimal("10"), status: ORDER_STATUS.FILLED });
    prismaMock.order.findUniqueOrThrow.mockResolvedValue(order);
    prismaMock.trade.aggregate
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("10") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } });
    prismaMock.order.update.mockImplementation(async ({ data }: any) => ({ ...order, ...data }));

    const result = await syncOrderStatusFromTrades(order.id);

    expect(result.status).toBe(ORDER_STATUS.FILLED);
  });
});
""")
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_ts)

print("Patched package.json, rewrote execution.ts with the Phase 3 cleanup fixes, and wrote apps/api/test/ledger.execution.phase3-cleanup.test.ts.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 3 cleanup patch applied."
