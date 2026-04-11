#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])

pkg_path = root / 'apps/api/package.json'
pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault('scripts', {})
scripts.setdefault('test:ledger:execution', 'vitest run -- ledger.execution.test.ts')
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

exec_path = root / 'apps/api/src/lib/ledger/execution.ts'
exec_path.write_text('''import { Decimal } from "@prisma/client/runtime/library";
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
  const remaining = new Decimal(order.qty).minus(executed);
  return remaining.lessThan(0) ? new Decimal(0) : remaining;
}

async function syncOrderStatus(orderId: bigint, db: LedgerDbClient): Promise<Order> {
  const order = await db.order.findUniqueOrThrow({ where: { id: orderId } });
  const remaining = await getOrderRemainingQty(order, db);
  return db.order.update({
    where: { id: orderId },
    data: {
      status: remaining.lessThanOrEqualTo(0) ? "FILLED" : "OPEN",
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

    await syncOrderStatus(buyOrder.id, db);
    await syncOrderStatus(sellOrder.id, db);

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
  const remainingQty = new Decimal(order.qty).minus(executedQty);
  const safeRemaining = remainingQty.lessThan(0) ? new Decimal(0) : remainingQty;

  if (ledgerTransactions.length !== trades.length) {
    throw new Error("Trade to ledger transaction count mismatch for order reconciliation.");
  }

  return {
    orderId: String(order.id),
    status: order.status,
    tradeCount: trades.length,
    ledgerTransactionCount: ledgerTransactions.length,
    executedQty: executedQty.toString(),
    remainingQty: safeRemaining.toString(),
  };
}
''')

index_path = root / 'apps/api/src/lib/ledger/index.ts'
index_text = index_path.read_text()
if 'export * from "./execution";' not in index_text:
    index_text = index_text.rstrip() + '\n\nexport * from "./execution";\n'
    index_path.write_text(index_text)

trade_path = root / 'apps/api/src/routes/trade.ts'
trade_path.write_text('''import { Router } from "express";

import { TradeMode, Prisma } from "@prisma/client";
import { z } from "zod";

import { prisma } from "../lib/prisma";
import {
  executeLimitOrderAgainstBook,
  getOrderRemainingQty,
  reconcileOrderExecution,
  reconcileTradeSettlement,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
  settleMatchedTrade,
} from "../lib/ledger";
import { enforceMandate, bumpOrdersPlaced } from "../middleware/ibac";

const router = Router();

const orderSchema = z.object({
  symbol: z.string().min(3).max(40),
  side: z.enum(["BUY", "SELL"]),
  type: z.enum(["LIMIT", "MARKET"]),
  qty: z.string(),
  price: z.string().optional(),
  tif: z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional(),
  mode: z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
  quoteFeeBps: z.string().optional(),
});

const fillSchema = z.object({
  buyOrderId: z.union([z.string(), z.number(), z.bigint()]),
  sellOrderId: z.union([z.string(), z.number(), z.bigint()]),
  symbol: z.string().min(3).max(40),
  qty: z.string(),
  price: z.string(),
  mode: z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
  quoteFee: z.string().optional(),
});

router.post("/orders", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const payload = orderSchema.parse(req.body);
    const principal = req.principal;

    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    if (payload.type !== "LIMIT") {
      return res.status(400).json({ error: "Phase 2D only wires LIMIT order execution and ledger booking." });
    }

    if (!payload.price) {
      return res.status(400).json({ error: "LIMIT orders require price." });
    }

    const result = await prisma.$transaction(async (tx) => {
      const order = await tx.order.create({
        data: {
          symbol: payload.symbol,
          side: payload.side,
          price: new Prisma.Decimal(payload.price),
          qty: new Prisma.Decimal(payload.qty),
          status: "OPEN",
          mode: payload.mode as TradeMode,
          userId: principal.userId,
        },
      });

      const ledgerReservation = await reserveOrderOnPlacement(
        {
          orderId: order.id,
          userId: principal.userId,
          symbol: payload.symbol,
          side: payload.side,
          qty: payload.qty,
          price: payload.price,
          mode: payload.mode as TradeMode,
        },
        tx,
      );

      const execution = await executeLimitOrderAgainstBook(
        {
          orderId: order.id,
          quoteFeeBps: payload.quoteFeeBps ?? "0",
        },
        tx,
      );

      const orderReconciliation = await reconcileOrderExecution(order.id, tx);

      return { order, ledgerReservation, execution, orderReconciliation };
    });

    await bumpOrdersPlaced(principal.mandateId ?? principal.mandate?.id);

    return res.json({ ok: true, ...result });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to place order" });
  }
});

router.post("/orders/:orderId/cancel", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const principal = req.principal;
    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    const orderId = BigInt(String(req.params.orderId));
    const order = await prisma.order.findUnique({ where: { id: orderId } });

    if (!order || order.userId !== principal.userId) {
      return res.status(404).json({ error: "Order not found" });
    }

    const remainingQty = await getOrderRemainingQty(order, prisma);
    if (remainingQty.lessThanOrEqualTo(0) || order.status !== "OPEN") {
      return res.status(409).json({ error: "Only OPEN orders with remaining quantity can be cancelled" });
    }

    const [ledgerRelease, cancelledOrder] = await prisma.$transaction(async (tx) => {
      const release = await releaseOrderOnCancel(
        {
          orderId: order.id,
          userId: order.userId,
          symbol: order.symbol,
          side: order.side,
          qty: remainingQty,
          price: order.price,
          mode: order.mode,
          reason: "CANCEL",
        },
        tx,
      );

      const updated = await tx.order.update({
        where: { id: order.id },
        data: { status: "CANCELLED" },
      });

      return [release, updated] as const;
    });

    return res.json({ ok: true, order: cancelledOrder, ledgerRelease, remainingQty: remainingQty.toString() });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to cancel order" });
  }
});

router.post("/fills/demo", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const principal = req.principal;
    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    const payload = fillSchema.parse(req.body);

    const result = await prisma.$transaction(async (tx) => {
      const buyOrderId = BigInt(String(payload.buyOrderId));
      const sellOrderId = BigInt(String(payload.sellOrderId));

      const [buyOrder, sellOrder] = await Promise.all([
        tx.order.findUnique({ where: { id: buyOrderId } }),
        tx.order.findUnique({ where: { id: sellOrderId } }),
      ]);

      if (!buyOrder || !sellOrder) {
        throw new Error("Both buy and sell orders are required.");
      }
      if (buyOrder.side !== "BUY" || sellOrder.side !== "SELL") {
        throw new Error("Fill settlement requires a BUY order and a SELL order.");
      }
      if (buyOrder.symbol !== payload.symbol || sellOrder.symbol !== payload.symbol) {
        throw new Error("Both orders must match the fill symbol.");
      }
      if (buyOrder.mode !== (payload.mode as TradeMode) || sellOrder.mode !== (payload.mode as TradeMode)) {
        throw new Error("Both orders must match the fill mode.");
      }
      if (buyOrder.status !== "OPEN" || sellOrder.status !== "OPEN") {
        throw new Error("Only OPEN orders can be settled in the Phase 2C/2D demo fill path.");
      }

      const trade = await tx.trade.create({
        data: {
          symbol: payload.symbol,
          price: new Prisma.Decimal(payload.price),
          qty: new Prisma.Decimal(payload.qty),
          mode: payload.mode as TradeMode,
          buyOrderId: buyOrder.id,
          sellOrderId: sellOrder.id,
        },
      });

      const ledgerSettlement = await settleMatchedTrade(
        {
          tradeRef: trade.id.toString(),
          buyOrderId: buyOrder.id,
          sellOrderId: sellOrder.id,
          symbol: payload.symbol,
          qty: payload.qty,
          price: payload.price,
          mode: payload.mode as TradeMode,
          quoteFee: payload.quoteFee ?? "0",
        },
        tx,
      );

      await tx.order.updateMany({
        where: {
          id: { in: [buyOrder.id, sellOrder.id] },
        },
        data: {
          status: "FILLED",
        },
      });

      const reconciliation = await reconcileTradeSettlement(trade.id, tx);
      const buyOrderReconciliation = await reconcileOrderExecution(buyOrder.id, tx);
      const sellOrderReconciliation = await reconcileOrderExecution(sellOrder.id, tx);

      return { trade, ledgerSettlement, reconciliation, buyOrderReconciliation, sellOrderReconciliation };
    });

    return res.json({ ok: true, ...result });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to settle fill" });
  }
});

export default router;
''')

test_path = root / 'apps/api/test/ledger.execution.test.ts'
test_path.write_text('''import { describe, expect, it } from "vitest";

import {
  computeBuyPriceImprovementReleaseAmount,
  computeQuoteFeeAmount,
  isCrossingLimitOrder,
} from "../src/lib/ledger/execution";

describe("ledger execution helper", () => {
  it("detects crossing prices for buy and sell limit orders", () => {
    expect(isCrossingLimitOrder("BUY", "100", "99")).toBe(true);
    expect(isCrossingLimitOrder("BUY", "100", "101")).toBe(false);
    expect(isCrossingLimitOrder("SELL", "100", "101")).toBe(true);
    expect(isCrossingLimitOrder("SELL", "100", "99")).toBe(false);
  });

  it("computes quote fees from bps", () => {
    expect(computeQuoteFeeAmount("1000", "25").toString()).toBe("2.5");
    expect(computeQuoteFeeAmount("1000", "0").toString()).toBe("0");
  });

  it("computes buy-side price improvement release amount", () => {
    expect(computeBuyPriceImprovementReleaseAmount("100", "90", "5").toString()).toBe("50");
    expect(computeBuyPriceImprovementReleaseAmount("100", "100", "5").toString()).toBe("0");
  });
});
''')
PY

echo "Patched package.json, added execution helper/test, re-exported execution helper, and wired order placement into actual execution settlement for Phase 2D."
echo "Phase 2D patch applied."
