#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])

def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")
    return path.read_text()

def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)

pkg_path = root / "apps/api/package.json"
pkg = json.loads(read(pkg_path))
scripts = pkg.setdefault("scripts", {})
scripts.setdefault("test:ledger:settlement", "vitest run -- ledger.reconciliation.test.ts")
write(pkg_path, json.dumps(pkg, indent=2) + "\n")

recon_path = root / "apps/api/src/lib/ledger/reconciliation.ts"
recon_code = '''import { Decimal } from "@prisma/client/runtime/library";
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
'''
write(recon_path, recon_code)

ledger_index_path = root / "apps/api/src/lib/ledger/index.ts"
ledger_index = read(ledger_index_path)
if 'export * from "./reconciliation";' not in ledger_index:
    ledger_index = ledger_index.rstrip() + '\n\nexport * from "./reconciliation";\n'
    write(ledger_index_path, ledger_index)

trade_path = root / "apps/api/src/routes/trade.ts"
trade_code = '''import { Router } from "express";

import { TradeMode, Prisma } from "@prisma/client";
import { z } from "zod";

import { prisma } from "../lib/prisma";
import {
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

    await bumpOrdersPlaced(principal.mandateId ?? principal.mandate?.id);

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
        throw new Error("Only OPEN orders can be settled in the Phase 2C demo fill path.");
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

      const ledgerSettlement = await settleMatchedTrade({
        tradeRef: trade.id.toString(),
        buyOrderId: buyOrder.id,
        sellOrderId: sellOrder.id,
        symbol: payload.symbol,
        qty: payload.qty,
        price: payload.price,
        mode: payload.mode as TradeMode,
        quoteFee: payload.quoteFee ?? "0",
      }, tx);

      await tx.order.updateMany({
        where: {
          id: { in: [buyOrder.id, sellOrder.id] },
        },
        data: {
          status: "FILLED",
        },
      });

      const reconciliation = await reconcileTradeSettlement(trade.id, tx);

      return { trade, ledgerSettlement, reconciliation };
    });

    return res.json({ ok: true, ...result });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to settle fill" });
  }
});

export default router;
'''
write(trade_path, trade_code)

test_path = root / "apps/api/test/ledger.reconciliation.test.ts"
test_code = '''import { Decimal } from "@prisma/client/runtime/library";
import { describe, expect, it } from "vitest";

import { assertTradeSettlementConsistency } from "../src/lib/ledger/reconciliation";

describe("ledger trade settlement reconciliation", () => {
  it("accepts a consistent trade settlement record", () => {
    const result = assertTradeSettlementConsistency({
      trade: {
        id: 101n,
        symbol: "BTC-USD",
        qty: new Decimal("0.5"),
        price: new Decimal("60000"),
        mode: "PAPER",
        buyOrderId: 11n,
        sellOrderId: 22n,
      },
      ledgerTransaction: {
        referenceType: "ORDER_EVENT",
        referenceId: "101:FILL_SETTLEMENT",
        metadata: {
          tradeRef: "101",
          buyOrderId: "11",
          sellOrderId: "22",
          symbol: "BTC-USD",
          qty: "0.5",
          price: "60000",
          mode: "PAPER",
        },
        postings: [
          { assetCode: "USD", amount: "30000", side: "DEBIT" },
          { assetCode: "USD", amount: "29990", side: "CREDIT" },
          { assetCode: "USD", amount: "10", side: "CREDIT" },
          { assetCode: "BTC", amount: "0.5", side: "DEBIT" },
          { assetCode: "BTC", amount: "0.5", side: "CREDIT" },
        ],
      },
    });

    expect(result.ok).toBe(true);
    expect(result.referenceId).toBe("101:FILL_SETTLEMENT");
    expect(result.postingCount).toBe(5);
  });

  it("rejects mismatched settlement metadata", () => {
    expect(() =>
      assertTradeSettlementConsistency({
        trade: {
          id: 101n,
          symbol: "BTC-USD",
          qty: new Decimal("0.5"),
          price: new Decimal("60000"),
          mode: "PAPER",
          buyOrderId: 11n,
          sellOrderId: 22n,
        },
        ledgerTransaction: {
          referenceType: "ORDER_EVENT",
          referenceId: "101:FILL_SETTLEMENT",
          metadata: {
            tradeRef: "101",
            buyOrderId: "11",
            sellOrderId: "22",
            symbol: "ETH-USD",
            qty: "0.5",
            price: "60000",
            mode: "PAPER",
          },
          postings: [
            { assetCode: "USD", amount: "30000", side: "DEBIT" },
            { assetCode: "USD", amount: "30000", side: "CREDIT" },
            { assetCode: "BTC", amount: "0.5", side: "DEBIT" },
            { assetCode: "BTC", amount: "0.5", side: "CREDIT" },
          ],
        },
      }),
    ).toThrow(/metadata.symbol/i);
  });

  it("rejects ledger transactions without enough postings", () => {
    expect(() =>
      assertTradeSettlementConsistency({
        trade: {
          id: 101n,
          symbol: "BTC-USD",
          qty: new Decimal("0.5"),
          price: new Decimal("60000"),
          mode: "PAPER",
          buyOrderId: 11n,
          sellOrderId: 22n,
        },
        ledgerTransaction: {
          referenceType: "ORDER_EVENT",
          referenceId: "101:FILL_SETTLEMENT",
          metadata: {
            tradeRef: "101",
            buyOrderId: "11",
            sellOrderId: "22",
            symbol: "BTC-USD",
            qty: "0.5",
            price: "60000",
            mode: "PAPER",
          },
          postings: [
            { assetCode: "USD", amount: "30000", side: "DEBIT" },
          ],
        },
      }),
    ).toThrow(/must contain postings/i);
  });
});
'''
write(test_path, test_code)

print("Patched package.json, added reconciliation helper/test, re-exported reconciliation, and wired demo fill settlement into trade route for Phase 2C.")
PY

echo "Phase 2C patch applied."
