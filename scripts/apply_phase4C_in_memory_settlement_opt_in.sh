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
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
book_path = root / "apps/api/src/lib/matching/in-memory-order-book.ts"
engine_path = root / "apps/api/src/lib/matching/in-memory-matching-engine.ts"
submit_path = root / "apps/api/src/lib/matching/submit-limit-order.ts"
orders_path = root / "apps/api/src/routes/orders.ts"
trade_path = root / "apps/api/src/routes/trade.ts"
index_path = root / "apps/api/src/lib/matching/index.ts"
test_path = root / "apps/api/test/in-memory-settlement-integration.test.ts"

for p in [pkg_path, book_path, engine_path, submit_path, orders_path, trade_path, index_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:in-memory-settlement"] = "vitest run test/in-memory-settlement-integration.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

book_path.write_text(dedent("""\
import { Decimal } from "@prisma/client/runtime/library";
import { type OrderSide } from "@prisma/client";

import { sortMakersForTaker } from "../ledger/matching-priority";
import {
  assertFokCanFullyFill,
  assertPostOnlyWouldRest,
  deriveTifRestingAction,
  normalizeTimeInForce,
} from "../ledger/time-in-force";

type Decimalish = string | number | Decimal;

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

function minDecimal(a: Decimal, b: Decimal): Decimal {
  return a.lessThanOrEqualTo(b) ? a : b;
}

export type InMemoryBookOrder = {
  orderId: string;
  symbol: string;
  side: OrderSide;
  price: Decimal;
  remainingQty: Decimal;
  createdAt: Date;
  timeInForce: string;
};

export type InMemoryFill = {
  makerOrderId: string;
  takerOrderId: string;
  qty: string;
  price: string;
};

export class InMemoryOrderBook {
  private readonly bids: InMemoryBookOrder[] = [];
  private readonly asks: InMemoryBookOrder[] = [];

  add(order: Omit<InMemoryBookOrder, "price" | "remainingQty" | "createdAt"> & {
    price: Decimalish;
    remainingQty: Decimalish;
    createdAt?: Date | string | number;
  }): InMemoryBookOrder {
    const normalized: InMemoryBookOrder = {
      ...order,
      price: toDecimal(order.price),
      remainingQty: toDecimal(order.remainingQty),
      createdAt: order.createdAt instanceof Date ? order.createdAt : new Date(order.createdAt ?? Date.now()),
    };
    const side = normalized.side === "BUY" ? this.bids : this.asks;
    side.push(normalized);
    return normalized;
  }

  remove(orderId: string): boolean {
    const before = this.bids.length + this.asks.length;
    const nextBids = this.bids.filter((o) => o.orderId !== orderId);
    const nextAsks = this.asks.filter((o) => o.orderId !== orderId);
    this.bids.splice(0, this.bids.length, ...nextBids);
    this.asks.splice(0, this.asks.length, ...nextAsks);
    return before !== this.bids.length + this.asks.length;
  }

  snapshot(side: OrderSide): InMemoryBookOrder[] {
    const source = side === "BUY" ? this.bids : this.asks;
    return source.map((o) => ({ ...o }));
  }

  private oppositeFor(side: OrderSide): InMemoryBookOrder[] {
    return side === "BUY" ? this.asks : this.bids;
  }

  getBestOppositePrice(side: OrderSide): Decimal | null {
    const sortedOpposite = sortMakersForTaker(side, this.oppositeFor(side));
    return sortedOpposite[0]?.price ?? null;
  }

  getCrossingLiquidity(side: OrderSide, takerPrice: Decimalish): Decimal {
    const price = toDecimal(takerPrice);
    let total = new Decimal(0);

    for (const maker of sortMakersForTaker(side, this.oppositeFor(side))) {
      const crosses =
        side === "BUY"
          ? maker.price.lessThanOrEqualTo(price)
          : maker.price.greaterThanOrEqualTo(price);

      if (!crosses) break;
      if (maker.remainingQty.lessThanOrEqualTo(0)) continue;
      total = total.plus(maker.remainingQty);
    }

    return total;
  }

  matchIncoming(input: {
    orderId: string;
    symbol: string;
    side: OrderSide;
    price: Decimalish;
    qty: Decimalish;
    timeInForce?: string;
    createdAt?: Date | string | number;
  }): {
    fills: InMemoryFill[];
    remainingQty: string;
    tifAction: "KEEP_OPEN" | "CANCEL_REMAINDER" | "FILLED";
    restingOrderId: string | null;
  } {
    const tif = normalizeTimeInForce(input.timeInForce);
    const takerPrice = toDecimal(input.price);
    const initialQty = toDecimal(input.qty);
    let remaining = initialQty;

    const bestOppositePrice = this.getBestOppositePrice(input.side);

    if (tif === "POST_ONLY") {
      assertPostOnlyWouldRest(input.side, takerPrice, bestOppositePrice);
    }

    if (tif === "FOK") {
      const fillableLiquidity = this.getCrossingLiquidity(input.side, takerPrice);
      assertFokCanFullyFill(initialQty, fillableLiquidity);
    }

    const fills: InMemoryFill[] = [];
    const sortedOpposite = sortMakersForTaker(input.side, this.oppositeFor(input.side));

    for (const maker of sortedOpposite) {
      if (remaining.lessThanOrEqualTo(0)) break;

      const crosses =
        input.side === "BUY"
          ? maker.price.lessThanOrEqualTo(takerPrice)
          : maker.price.greaterThanOrEqualTo(takerPrice);

      if (!crosses) break;
      if (maker.remainingQty.lessThanOrEqualTo(0)) continue;

      const fillQty = minDecimal(remaining, maker.remainingQty);
      maker.remainingQty = maker.remainingQty.minus(fillQty);
      remaining = remaining.minus(fillQty);

      fills.push({
        makerOrderId: maker.orderId,
        takerOrderId: input.orderId,
        qty: fillQty.toString(),
        price: maker.price.toString(),
      });

      if (maker.remainingQty.lessThanOrEqualTo(0)) {
        this.remove(maker.orderId);
      } else {
        const bookSide = maker.side === "BUY" ? this.bids : this.asks;
        const idx = bookSide.findIndex((o) => o.orderId === maker.orderId);
        if (idx >= 0) {
          bookSide[idx] = maker;
        }
      }
    }

    const executedQty = initialQty.minus(remaining);
    const tifAction = deriveTifRestingAction(tif, executedQty, initialQty);

    let restingOrderId: string | null = null;
    if (tifAction === "KEEP_OPEN" && remaining.greaterThan(0)) {
      const resting = this.add({
        orderId: input.orderId,
        symbol: input.symbol,
        side: input.side,
        price: takerPrice,
        remainingQty: remaining,
        createdAt: input.createdAt,
        timeInForce: tif,
      });
      restingOrderId = resting.orderId;
    }

    return {
      fills,
      remainingQty: remaining.toString(),
      tifAction,
      restingOrderId,
    };
  }
}
"""))

engine_path.write_text(dedent("""\
import { Decimal } from "@prisma/client/runtime/library";
import {
  type PrismaClient,
  type Prisma,
  type Order,
} from "@prisma/client";

import {
  getOrderRemainingQty,
  releaseBuyPriceImprovement,
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
} from "../ledger/execution";
import { releaseOrderOnCancel, settleMatchedTrade } from "../ledger/order-lifecycle";
import { reconcileTradeSettlement } from "../ledger/reconciliation";
import { ORDER_STATUS, assertValidTransition, deriveOrderStatus } from "../ledger/order-state";
import type {
  MatchingEngineExecutionInput,
  MatchingEngineExecutionResult,
  MatchingEnginePort,
} from "./engine-port";
import { InMemoryOrderBook } from "./in-memory-order-book";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export class InMemoryMatchingEngine implements MatchingEnginePort {
  readonly name = "IN_MEMORY_MATCHER";
  private readonly books = new Map<string, InMemoryOrderBook>();

  private getBookKey(symbol: string, mode: string): string {
    return `${symbol}:${mode}`;
  }

  private getBook(symbol: string, mode: string): InMemoryOrderBook {
    const key = this.getBookKey(symbol, mode);
    let existing = this.books.get(key);
    if (!existing) {
      existing = new InMemoryOrderBook();
      this.books.set(key, existing);
    }
    return existing;
  }

  async executeLimitOrder(
    input: MatchingEngineExecutionInput,
    db: LedgerDbClient,
  ): Promise<MatchingEngineExecutionResult> {
    const order = await db.order.findUniqueOrThrow({
      where: { id: BigInt(String(input.orderId)) },
    });

    const remainingQty = await getOrderRemainingQty(order as any, db as any);
    const book = this.getBook(order.symbol, order.mode);

    const bookExecution = book.matchIncoming({
      orderId: order.id.toString(),
      symbol: order.symbol,
      side: order.side as any,
      price: new Decimal(order.price),
      qty: remainingQty,
      timeInForce: (order as any).timeInForce ?? "GTC",
      createdAt: order.createdAt,
    });

    const settlementResults: Array<Record<string, unknown>> = [];

    for (const fill of bookExecution.fills) {
      const makerOrder = await db.order.findUniqueOrThrow({
        where: { id: BigInt(fill.makerOrderId) },
      });

      const fillQty = new Decimal(fill.qty);
      const executionPrice = new Decimal(fill.price);
      const quoteFee = new Decimal(0);

      const buyOrder = order.side === "BUY" ? order : makerOrder;
      const sellOrder = order.side === "SELL" ? order : makerOrder;

      const trade = await db.trade.create({
        data: {
          symbol: order.symbol,
          price: executionPrice,
          qty: fillQty,
          mode: order.mode,
          buyOrderId: buyOrder.id,
          sellOrderId: sellOrder.id,
        },
      });

      const ledgerSettlement = await settleMatchedTrade(
        {
          tradeRef: trade.id.toString(),
          buyOrderId: buyOrder.id,
          sellOrderId: sellOrder.id,
          symbol: order.symbol,
          qty: fillQty,
          price: executionPrice,
          mode: order.mode,
          quoteFee,
        },
        db as any,
      );

      const buyPriceImprovementRelease = await releaseBuyPriceImprovement(
        {
          tradeRef: trade.id.toString(),
          orderId: buyOrder.id,
          userId: buyOrder.userId,
          symbol: order.symbol,
          limitPrice: buyOrder.price,
          executionPrice,
          fillQty,
          mode: order.mode,
        },
        db as any,
      );

      const tradeReconciliation = await reconcileTradeSettlement(trade.id, db as any);

      await syncOrderStatusFromTrades(buyOrder.id, db as any);
      await syncOrderStatusFromTrades(sellOrder.id, db as any);

      settlementResults.push({
        trade,
        ledgerSettlement,
        buyPriceImprovementRelease,
        tradeReconciliation,
      });
    }

    let finalOrder: Order = await db.order.findUniqueOrThrow({
      where: { id: order.id },
    });

    const finalRemaining = await getOrderRemainingQty(finalOrder as any, db as any);
    const executedQty = new Decimal(order.qty).minus(finalRemaining);

    if (bookExecution.tifAction === "CANCEL_REMAINDER" && finalRemaining.greaterThan(0)) {
      await releaseOrderOnCancel(
        {
          orderId: finalOrder.id,
          userId: finalOrder.userId,
          symbol: finalOrder.symbol,
          side: finalOrder.side,
          qty: finalRemaining,
          price: finalOrder.price,
          mode: finalOrder.mode,
          reason: "CANCEL",
        },
        db as any,
      );

      const currentDerivedStatus = deriveOrderStatus(
        finalOrder.status,
        finalOrder.qty,
        executedQty,
      );
      assertValidTransition(currentDerivedStatus, ORDER_STATUS.CANCELLED);

      finalOrder = await db.order.update({
        where: { id: finalOrder.id },
        data: { status: ORDER_STATUS.CANCELLED as any },
      });
    }

    const orderReconciliation =
      settlementResults.length > 0
        ? await reconcileOrderExecution(order.id, db as any)
        : {
            orderId: order.id.toString(),
            status: finalOrder.status,
            expectedStatus: finalOrder.status,
            tradeCount: 0,
            ledgerTransactionCount: 0,
            executedQty: executedQty.toString(),
            remainingQty: finalRemaining.toString(),
          };

    return {
      execution: {
        order: {
          id: finalOrder.id,
          symbol: finalOrder.symbol,
          side: finalOrder.side,
          price: finalOrder.price,
          qty: finalOrder.qty,
          status: finalOrder.status,
          mode: finalOrder.mode,
          createdAt: finalOrder.createdAt,
          timeInForce: (finalOrder as any).timeInForce ?? "GTC",
        },
        fills: bookExecution.fills,
        remainingQty: finalRemaining.toString(),
        tifAction: bookExecution.tifAction,
        restingOrderId: bookExecution.restingOrderId,
        settlements: settlementResults,
      },
      orderReconciliation,
      engine: this.name,
    };
  }
}

export const inMemoryMatchingEngine = new InMemoryMatchingEngine();
"""))

submit_text = submit_path.read_text()
if "preferredEngine?: string | null;" not in submit_text:
    submit_text = submit_text.replace(
        '  source: "HUMAN" | "AGENT";\n};',
        '  source: "HUMAN" | "AGENT";\n  preferredEngine?: string | null;\n};',
        1,
    )
if 'const selectedEngine = engine ?? selectMatchingEngine(input.preferredEngine as any);' not in submit_text:
    submit_text = submit_text.replace(
        '  const selectedEngine = engine ?? selectMatchingEngine();',
        '  const selectedEngine = engine ?? selectMatchingEngine(input.preferredEngine as any);',
        1,
    )
submit_path.write_text(submit_text)

orders_text = orders_path.read_text()
if 'const preferredEngine =' not in orders_text:
    parse_anchor = '      const payload = placeOrderSchema.parse(req.body);\n'
    if parse_anchor in orders_text:
        orders_text = orders_text.replace(
            parse_anchor,
            parse_anchor + '      const preferredEngine = process.env.ALLOW_IN_MEMORY_MATCHING === "true"\n        ? (req.get("x-matching-engine") ?? undefined)\n        : undefined;\n',
            1,
        )
if 'preferredEngine,' not in orders_text:
    orders_text = orders_text.replace(
        '          source: "HUMAN",\n',
        '          source: "HUMAN",\n          preferredEngine,\n',
        1,
    )
orders_path.write_text(orders_text)

trade_text = trade_path.read_text()
if 'const preferredEngine =' not in trade_text:
    payload_anchor = '      const payload = placeOrderSchema.parse(req.body);\n'
    if payload_anchor in trade_text:
        trade_text = trade_text.replace(
            payload_anchor,
            payload_anchor + '      const preferredEngine = process.env.ALLOW_IN_MEMORY_MATCHING === "true"\n        ? (req.get("x-matching-engine") ?? undefined)\n        : undefined;\n',
            1,
        )
if 'preferredEngine,' not in trade_text:
    trade_text = trade_text.replace(
        '          source: "AGENT",\n',
        '          source: "AGENT",\n          preferredEngine,\n',
        1,
    )
trade_path.write_text(trade_text)

index_text = index_path.read_text()
for export_line in [
    'export * from "./in-memory-order-book";',
    'export * from "./in-memory-matching-engine";',
    'export * from "./select-engine";',
]:
    if export_line not in index_text:
        index_text = index_text.rstrip() + "\n" + export_line + "\n"
index_path.write_text(index_text)

test_path.write_text(dedent("""\
import { beforeEach, describe, expect, it, vi } from "vitest";
import { Decimal } from "@prisma/client/runtime/library";

const {
  prismaMock,
  getOrderRemainingQty,
  releaseBuyPriceImprovement,
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
  settleMatchedTrade,
  releaseOrderOnCancel,
  reconcileTradeSettlement,
  reserveOrderOnPlacement,
  selectMatchingEngine,
} = vi.hoisted(() => ({
  prismaMock: {
    order: {
      findUniqueOrThrow: vi.fn(),
      update: vi.fn(),
    },
    trade: {
      create: vi.fn(),
    },
    $transaction: vi.fn(),
  },
  getOrderRemainingQty: vi.fn(),
  releaseBuyPriceImprovement: vi.fn(),
  reconcileOrderExecution: vi.fn(),
  syncOrderStatusFromTrades: vi.fn(),
  settleMatchedTrade: vi.fn(),
  releaseOrderOnCancel: vi.fn(),
  reconcileTradeSettlement: vi.fn(),
  reserveOrderOnPlacement: vi.fn(),
  selectMatchingEngine: vi.fn(),
}));

vi.mock("../src/lib/ledger/execution", () => ({
  getOrderRemainingQty,
  releaseBuyPriceImprovement,
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
}));
vi.mock("../src/lib/ledger/order-lifecycle", () => ({
  settleMatchedTrade,
  releaseOrderOnCancel,
}));
vi.mock("../src/lib/ledger/reconciliation", () => ({
  reconcileTradeSettlement,
}));
vi.mock("../src/lib/ledger", () => ({
  reserveOrderOnPlacement,
}));
vi.mock("../src/lib/matching/select-engine", () => ({
  selectMatchingEngine,
}));

import { InMemoryMatchingEngine } from "../src/lib/matching/in-memory-matching-engine";
import { submitLimitOrder } from "../src/lib/matching/submit-limit-order";
import { InMemoryOrderBook } from "../src/lib/matching/in-memory-order-book";

describe("in-memory settlement integration", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.ALLOW_IN_MEMORY_MATCHING;
  });

  it("book rejects POST_ONLY crosses and FOK underfill before matching", () => {
    const book = new InMemoryOrderBook();
    book.add({
      orderId: "ask-1",
      symbol: "BTC-USD",
      side: "SELL",
      price: "99",
      remainingQty: "1",
      createdAt: new Date("2026-01-01T00:00:00Z"),
      timeInForce: "GTC",
    });

    expect(() =>
      book.matchIncoming({
        orderId: "buy-post",
        symbol: "BTC-USD",
        side: "BUY",
        price: "100",
        qty: "1",
        timeInForce: "POST_ONLY",
      }),
    ).toThrow(/POST_ONLY/i);

    expect(() =>
      book.matchIncoming({
        orderId: "buy-fok",
        symbol: "BTC-USD",
        side: "BUY",
        price: "100",
        qty: "2",
        timeInForce: "FOK",
      }),
    ).toThrow(/FOK/i);
  });

  it("in-memory engine creates trades and ledger settlement for matched fills", async () => {
    const sellOrder = {
      id: 1n,
      userId: "seller",
      symbol: "BTC-USD",
      side: "SELL",
      price: new Decimal("99"),
      qty: new Decimal("3"),
      status: "OPEN",
      mode: "PAPER",
      createdAt: new Date("2026-01-01T00:00:00Z"),
      timeInForce: "GTC",
    };
    const buyOrder = {
      id: 2n,
      userId: "buyer",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      qty: new Decimal("2"),
      status: "OPEN",
      mode: "PAPER",
      createdAt: new Date("2026-01-01T00:01:00Z"),
      timeInForce: "IOC",
    };

    prismaMock.order.findUniqueOrThrow
      .mockResolvedValueOnce(sellOrder)
      .mockResolvedValueOnce(sellOrder)
      .mockResolvedValueOnce(buyOrder)
      .mockResolvedValueOnce(sellOrder)
      .mockResolvedValueOnce(buyOrder)
      .mockResolvedValueOnce(buyOrder);

    prismaMock.trade.create.mockResolvedValue({
      id: 500n,
      symbol: "BTC-USD",
      qty: new Decimal("2"),
      price: new Decimal("99"),
      buyOrderId: 2n,
      sellOrderId: 1n,
      mode: "PAPER",
    });
    prismaMock.order.update.mockResolvedValue({
      ...buyOrder,
      status: "CANCELLED",
    });

    getOrderRemainingQty
      .mockResolvedValueOnce(new Decimal("3"))
      .mockResolvedValueOnce(new Decimal("2"))
      .mockResolvedValueOnce(new Decimal("2"));

    settleMatchedTrade.mockResolvedValue({ id: "ltx-1" });
    releaseBuyPriceImprovement.mockResolvedValue({ id: "ltx-2" });
    reconcileTradeSettlement.mockResolvedValue({ ok: true });
    syncOrderStatusFromTrades.mockResolvedValue(undefined);
    reconcileOrderExecution.mockResolvedValue({ ok: true });
    releaseOrderOnCancel.mockResolvedValue({ id: "ltx-3" });

    const engine = new InMemoryMatchingEngine();

    const first = await engine.executeLimitOrder({ orderId: sellOrder.id }, prismaMock as any);
    const second = await engine.executeLimitOrder({ orderId: buyOrder.id }, prismaMock as any);

    expect((first.execution as any).restingOrderId).toBe("1");
    expect(prismaMock.trade.create).toHaveBeenCalledTimes(1);
    expect(settleMatchedTrade).toHaveBeenCalledTimes(1);
    expect(releaseBuyPriceImprovement).toHaveBeenCalledTimes(1);
    expect(syncOrderStatusFromTrades).toHaveBeenCalledTimes(2);
    expect(reconcileTradeSettlement).toHaveBeenCalledTimes(1);
    expect((second.execution as any).fills[0]).toEqual(
      expect.objectContaining({ makerOrderId: "1", qty: "2", price: "99" }),
    );
  });

  it("submitLimitOrder selects preferred engine through the selector seam when no explicit engine is injected", async () => {
    const tx = {
      order: {
        create: vi.fn().mockResolvedValue({
          id: 123n,
          symbol: "BTC-USD",
          side: "BUY",
          price: "100",
          qty: "1",
          status: "OPEN",
          timeInForce: "GTC",
          mode: "PAPER",
          userId: "user-1",
        }),
      },
    };

    const fakeDb = {
      $transaction: vi.fn(async (fn: any) => fn(tx)),
    };

    reserveOrderOnPlacement.mockResolvedValue({ id: "reserve-1" });
    selectMatchingEngine.mockReturnValue({
      name: "IN_MEMORY_MATCHER",
      executeLimitOrder: vi.fn().mockResolvedValue({
        execution: { fills: [], remainingQty: "1", tifAction: "KEEP_OPEN", restingOrderId: "123" },
        orderReconciliation: { ok: true },
        engine: "IN_MEMORY_MATCHER",
      }),
    });

    const result = await submitLimitOrder(
      {
        userId: "user-1",
        symbol: "BTC-USD",
        side: "BUY",
        price: "100",
        qty: "1",
        mode: "PAPER" as any,
        source: "HUMAN",
        preferredEngine: "IN_MEMORY_MATCHER",
      },
      fakeDb as any,
    );

    expect(selectMatchingEngine).toHaveBeenCalledWith("IN_MEMORY_MATCHER");
    expect(result.engine).toBe("IN_MEMORY_MATCHER");
  });
});
"""))

print("Patched package.json, wired the in-memory engine into real downstream settlement, added controlled preferred-engine opt-in on routes, and wrote apps/api/test/in-memory-settlement-integration.test.ts for Phase 4C.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4C patch applied."
