#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])

# package.json
pkg_path = root / "apps/api/package.json"
pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts.setdefault("test:ledger:lifecycle", "vitest run -- ledger.order-lifecycle.test.ts")
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

# order-lifecycle helper
order_lifecycle_path = root / "apps/api/src/lib/ledger/order-lifecycle.ts"
order_lifecycle_path.parent.mkdir(parents=True, exist_ok=True)
order_lifecycle_path.write_text('''import { Decimal } from "@prisma/client/runtime/library";
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
''')

# patch ledger index re-exports
idx_path = root / "apps/api/src/lib/ledger/index.ts"
idx = idx_path.read_text()
if './order-lifecycle' not in idx and 'order-lifecycle' not in idx:
    idx += '\nexport * from "./order-lifecycle";\n'
idx_path.write_text(idx)

# patch trade.ts replace whole file for safe integration
trade_path = root / "apps/api/src/routes/trade.ts"
trade_path.write_text('''import { Router } from "express";

import { TradeMode, Prisma } from "@prisma/client";
import { z } from "zod";

import { prisma } from "../lib/prisma";
import {
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
} from "../lib/ledger/order-lifecycle";
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
});

router.post("/orders", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const payload = orderSchema.parse(req.body);
    const principal = req.principal;

    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    if (payload.type !== "LIMIT") {
      return res.status(400).json({ error: "Phase 2B only wires LIMIT order ledger booking." });
    }

    if (!payload.price) {
      return res.status(400).json({ error: "LIMIT orders require price." });
    }

    const order = await prisma.order.create({
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

    const ledgerReservation = await reserveOrderOnPlacement({
      orderId: order.id,
      userId: principal.userId,
      symbol: payload.symbol,
      side: payload.side,
      qty: payload.qty,
      price: payload.price,
      mode: payload.mode as TradeMode,
    });

    await bumpOrdersPlaced(principal.agentId, principal.mandate.id, new Date().toISOString().slice(0, 10));

    return res.json({ ok: true, order, ledgerReservation });
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

    if (order.status !== "OPEN") {
      return res.status(409).json({ error: "Only OPEN orders can be cancelled" });
    }

    const [ledgerRelease, cancelledOrder] = await prisma.$transaction(async (tx) => {
      const release = await releaseOrderOnCancel({
        orderId: order.id,
        userId: order.userId,
        symbol: order.symbol,
        side: order.side,
        qty: order.qty,
        price: order.price,
        mode: order.mode,
        reason: "CANCEL",
      }, tx);

      const updated = await tx.order.update({
        where: { id: order.id },
        data: { status: "CANCELLED" },
      });

      return [release, updated] as const;
    });

    return res.json({ ok: true, order: cancelledOrder, ledgerRelease });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to cancel order" });
  }
});

export default router;
''')

# add tests
ledger_test_path = root / "apps/api/test/ledger.order-lifecycle.test.ts"
ledger_test_path.parent.mkdir(parents=True, exist_ok=True)
ledger_test_path.write_text('''import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  ensureUserLedgerAccounts,
  ensureSystemLedgerAccounts,
  postLedgerTransaction,
} = vi.hoisted(() => ({
  prismaMock: {
    market: { findUnique: vi.fn() },
    ledgerPosting: { findMany: vi.fn() },
    ledgerTransaction: { findFirst: vi.fn() },
    order: { findUnique: vi.fn() },
  },
  ensureUserLedgerAccounts: vi.fn(),
  ensureSystemLedgerAccounts: vi.fn(),
  postLedgerTransaction: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/ledger/accounts", () => ({
  ensureUserLedgerAccounts,
  ensureSystemLedgerAccounts,
}));
vi.mock("../src/lib/ledger/service", () => ({ postLedgerTransaction }));

import { Decimal } from "@prisma/client/runtime/library";
import { reserveOrderOnPlacement, releaseOrderOnCancel, settleMatchedTrade } from "../src/lib/ledger/order-lifecycle";

describe("ledger order lifecycle", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.market.findUnique.mockResolvedValue({ symbol: "BTC-USD", baseAsset: "BTC", quoteAsset: "USD" });
    prismaMock.ledgerTransaction.findFirst.mockResolvedValue(null);
    prismaMock.ledgerPosting.findMany.mockResolvedValue([{ side: "CREDIT", amount: "100000.00" }]);
    ensureUserLedgerAccounts.mockResolvedValue({ available: { id: "acct-available" }, held: { id: "acct-held" } });
    ensureSystemLedgerAccounts.mockResolvedValue({ feeRevenue: { id: "fee-revenue" } });
    postLedgerTransaction.mockResolvedValue({ id: "ltx-1" });
  });

  it("reserves quote asset from available to held for BUY limit orders", async () => {
    await reserveOrderOnPlacement({
      orderId: "101",
      userId: "user-1",
      symbol: "BTC-USD",
      side: "BUY",
      qty: "2",
      price: "100",
      mode: "PAPER",
    });

    expect(postLedgerTransaction).toHaveBeenCalledWith(
      expect.objectContaining({
        referenceId: "101:PLACE_HOLD",
        postings: [
          expect.objectContaining({ accountId: "acct-available", assetCode: "USD", side: "DEBIT", amount: new Decimal("200") }),
          expect.objectContaining({ accountId: "acct-held", assetCode: "USD", side: "CREDIT", amount: new Decimal("200") }),
        ],
      }),
      expect.anything(),
    );
  });

  it("releases held funds back to available on cancellation", async () => {
    await releaseOrderOnCancel({
      orderId: "101",
      userId: "user-1",
      symbol: "BTC-USD",
      side: "BUY",
      qty: "2",
      price: "100",
      mode: "PAPER",
    });

    expect(postLedgerTransaction).toHaveBeenCalledWith(
      expect.objectContaining({
        referenceId: "101:CANCEL_RELEASE",
        postings: [
          expect.objectContaining({ accountId: "acct-held", assetCode: "USD", side: "DEBIT", amount: new Decimal("200") }),
          expect.objectContaining({ accountId: "acct-available", assetCode: "USD", side: "CREDIT", amount: new Decimal("200") }),
        ],
      }),
      expect.anything(),
    );
  });

  it("settles matched trades between counterparties plus fee revenue", async () => {
    prismaMock.order.findUnique
      .mockResolvedValueOnce({ id: 1n, userId: "buyer-1", symbol: "BTC-USD", side: "BUY", qty: new Decimal("2"), price: new Decimal("100"), mode: "PAPER", status: "OPEN" })
      .mockResolvedValueOnce({ id: 2n, userId: "seller-1", symbol: "BTC-USD", side: "SELL", qty: new Decimal("2"), price: new Decimal("100"), mode: "PAPER", status: "OPEN" });

    ensureUserLedgerAccounts
      .mockResolvedValueOnce({ available: { id: "buyer-base-available" }, held: { id: "buyer-base-held" } })
      .mockResolvedValueOnce({ available: { id: "buyer-quote-available" }, held: { id: "buyer-quote-held" } })
      .mockResolvedValueOnce({ available: { id: "seller-base-available" }, held: { id: "seller-base-held" } })
      .mockResolvedValueOnce({ available: { id: "seller-quote-available" }, held: { id: "seller-quote-held" } });

    prismaMock.ledgerPosting.findMany
      .mockResolvedValueOnce([{ side: "CREDIT", amount: "500.00" }])
      .mockResolvedValueOnce([{ side: "CREDIT", amount: "5.00" }]);

    await settleMatchedTrade({
      tradeRef: "trade-1",
      buyOrderId: "1",
      sellOrderId: "2",
      symbol: "BTC-USD",
      qty: "2",
      price: "100",
      mode: "PAPER",
      quoteFee: "5",
    });

    expect(postLedgerTransaction).toHaveBeenCalledWith(
      expect.objectContaining({
        referenceId: "trade-1:FILL_SETTLEMENT",
        postings: [
          expect.objectContaining({ accountId: "buyer-quote-held", assetCode: "USD", side: "DEBIT", amount: new Decimal("200") }),
          expect.objectContaining({ accountId: "seller-quote-available", assetCode: "USD", side: "CREDIT", amount: new Decimal("195") }),
          expect.objectContaining({ accountId: "fee-revenue", assetCode: "USD", side: "CREDIT", amount: new Decimal("5") }),
          expect.objectContaining({ accountId: "seller-base-held", assetCode: "BTC", side: "DEBIT", amount: new Decimal("2") }),
          expect.objectContaining({ accountId: "buyer-base-available", assetCode: "BTC", side: "CREDIT", amount: new Decimal("2") }),
        ],
      }),
      expect.anything(),
    );
  });
});
''')

print("Patched package.json, added ledger order lifecycle helper/test, re-exported ledger helper, and wired trade route place/cancel ledger booking for Phase 2B.")
PY

echo "Phase 2B patch applied."
