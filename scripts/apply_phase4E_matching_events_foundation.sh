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
book_path = root / "apps/api/src/lib/matching/in-memory-order-book.ts"
engine_path = root / "apps/api/src/lib/matching/in-memory-matching-engine.ts"
submit_path = root / "apps/api/src/lib/matching/submit-limit-order.ts"
events_path = root / "apps/api/src/lib/matching/matching-events.ts"
index_path = root / "apps/api/src/lib/matching/index.ts"
test_path = root / "apps/api/test/matching-events.test.ts"

for p in [pkg_path, book_path, engine_path, submit_path, index_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:events"] = "vitest run test/matching-events.test.ts"
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

export type InMemoryBookDelta = {
  symbol: string;
  bestBid: string | null;
  bestAsk: string | null;
  bidDepth: string;
  askDepth: string;
  bidOrders: number;
  askOrders: number;
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

  private summarizeSide(sideOrders: InMemoryBookOrder[]): {
    bestPrice: string | null;
    depth: string;
    count: number;
  } {
    const active = sideOrders.filter((o) => o.remainingQty.greaterThan(0));
    if (!active.length) {
      return { bestPrice: null, depth: "0", count: 0 };
    }

    const total = active.reduce((acc, order) => acc.plus(order.remainingQty), new Decimal(0));
    const best = active[0]?.price ?? null;
    return {
      bestPrice: best ? best.toString() : null,
      depth: total.toString(),
      count: active.length,
    };
  }

  getBookDelta(symbol: string): InMemoryBookDelta {
    const sortedBids = sortMakersForTaker("SELL", this.bids);
    const sortedAsks = sortMakersForTaker("BUY", this.asks);

    const bidSummary = this.summarizeSide(sortedBids);
    const askSummary = this.summarizeSide(sortedAsks);

    return {
      symbol,
      bestBid: bidSummary.bestPrice,
      bestAsk: askSummary.bestPrice,
      bidDepth: bidSummary.depth,
      askDepth: askSummary.depth,
      bidOrders: bidSummary.count,
      askOrders: askSummary.count,
    };
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
    bookDelta: InMemoryBookDelta;
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
      bookDelta: this.getBookDelta(input.symbol),
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
        bookDelta: bookExecution.bookDelta,
      },
      orderReconciliation,
      engine: this.name,
    };
  }
}

export const inMemoryMatchingEngine = new InMemoryMatchingEngine();
"""))

events_path.write_text(dedent("""\
import { Decimal } from "@prisma/client/runtime/library";

type MatchingEventType =
  | "ORDER_ACCEPTED"
  | "ORDER_FILL"
  | "ORDER_PARTIALLY_FILLED"
  | "ORDER_FILLED"
  | "ORDER_RESTED"
  | "ORDER_CANCELLED"
  | "BOOK_DELTA";

export type MatchingEvent = {
  type: MatchingEventType;
  ts: string;
  symbol: string;
  mode: string;
  engine: string;
  source: "HUMAN" | "AGENT";
  payload: Record<string, unknown>;
};

const matchingEvents: MatchingEvent[] = [];

function isZeroLike(value: unknown): boolean {
  if (value === null || value === undefined) return false;
  try {
    return new Decimal(String(value)).eq(0);
  } catch {
    return false;
  }
}

function normalizeFillPayload(fill: any): Record<string, unknown> {
  if (fill?.trade) {
    return {
      tradeId: String(fill.trade.id),
      qty: String(fill.trade.qty),
      price: String(fill.trade.price),
      buyOrderId: fill.trade.buyOrderId != null ? String(fill.trade.buyOrderId) : undefined,
      sellOrderId: fill.trade.sellOrderId != null ? String(fill.trade.sellOrderId) : undefined,
    };
  }

  return {
    makerOrderId: fill?.makerOrderId != null ? String(fill.makerOrderId) : undefined,
    takerOrderId: fill?.takerOrderId != null ? String(fill.takerOrderId) : undefined,
    qty: fill?.qty != null ? String(fill.qty) : undefined,
    price: fill?.price != null ? String(fill.price) : undefined,
  };
}

export function emitMatchingEvent(event: MatchingEvent): void {
  matchingEvents.push(event);
}

export function emitMatchingEvents(events: MatchingEvent[]): void {
  matchingEvents.push(...events);
}

export function listMatchingEvents(limit = 100): MatchingEvent[] {
  return matchingEvents.slice(-limit);
}

export function resetMatchingEventsForTests(): void {
  matchingEvents.length = 0;
}

export function buildMatchingEventsFromSubmission(input: {
  order: any;
  execution: any;
  engine: string;
  source: "HUMAN" | "AGENT";
  timeInForce: string;
}): MatchingEvent[] {
  const ts = new Date().toISOString();
  const order = input.order;
  const execution = input.execution ?? {};
  const events: MatchingEvent[] = [
    {
      type: "ORDER_ACCEPTED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        side: String(order.side),
        price: String(order.price),
        qty: String(order.qty),
        timeInForce: input.timeInForce,
      },
    },
  ];

  const fills = Array.isArray(execution.fills) ? execution.fills : [];
  for (const fill of fills) {
    events.push({
      type: "ORDER_FILL",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: normalizeFillPayload(fill),
    });
  }

  if (fills.length > 0) {
    events.push({
      type: isZeroLike(execution.remainingQty) ? "ORDER_FILLED" : "ORDER_PARTIALLY_FILLED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
        fillCount: fills.length,
      },
    });
  }

  if (execution.restingOrderId) {
    events.push({
      type: "ORDER_RESTED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(execution.restingOrderId),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
      },
    });
  }

  if (execution.tifAction === "CANCEL_REMAINDER" || String(execution.order?.status ?? order.status) === "CANCELLED") {
    events.push({
      type: "ORDER_CANCELLED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
        reason: execution.tifAction === "CANCEL_REMAINDER" ? "TIF_CANCEL_REMAINDER" : "CANCELLED",
      },
    });
  }

  if (execution.bookDelta) {
    events.push({
      type: "BOOK_DELTA",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: execution.bookDelta,
    });
  }

  return events;
}
"""))

submit_path.write_text(dedent("""\
import { Prisma, type PrismaClient, type TradeMode } from "@prisma/client";

import { prisma } from "../prisma";
import { reserveOrderOnPlacement } from "../ledger";
import { normalizeTimeInForce } from "../ledger/time-in-force";
import { ORDER_STATUS } from "../ledger/order-state";
import type { MatchingEnginePort } from "./engine-port";
import { selectMatchingEngine } from "./select-engine";
import { buildSymbolModeKey, runSerializedByKey } from "./serialized-dispatch";
import { buildMatchingEventsFromSubmission, emitMatchingEvents } from "./matching-events";

export type SubmitLimitOrderInput = {
  userId: string;
  symbol: string;
  side: "BUY" | "SELL";
  price: string;
  qty: string;
  mode: TradeMode;
  quoteFeeBps?: string;
  timeInForce?: string;
  source: "HUMAN" | "AGENT";
  preferredEngine?: string | null;
};

export async function submitLimitOrder(
  input: SubmitLimitOrderInput,
  db: PrismaClient = prisma,
  engine?: MatchingEnginePort,
) {
  const normalizedTimeInForce = normalizeTimeInForce(input.timeInForce);
  const selectedEngine = engine ?? selectMatchingEngine(input.preferredEngine as any);

  return db.$transaction(async (tx) => {
    const order = await tx.order.create({
      data: {
        symbol: input.symbol,
        side: input.side,
        price: new Prisma.Decimal(input.price),
        qty: new Prisma.Decimal(input.qty),
        status: ORDER_STATUS.OPEN,
        timeInForce: normalizedTimeInForce as any,
        mode: input.mode,
        userId: input.userId,
      },
    });

    const ledgerReservation = await reserveOrderOnPlacement(
      {
        orderId: order.id,
        userId: input.userId,
        symbol: input.symbol,
        side: input.side,
        qty: input.qty,
        price: input.price,
        mode: input.mode,
      },
      tx,
    );

    const executeThroughSelectedEngine = () =>
      selectedEngine.executeLimitOrder(
        {
          orderId: order.id,
          quoteFeeBps: input.quoteFeeBps ?? "0",
        },
        tx,
      );

    const engineResult =
      selectedEngine.name === "IN_MEMORY_MATCHER"
        ? await runSerializedByKey(
            buildSymbolModeKey(input.symbol, String(input.mode)),
            executeThroughSelectedEngine,
          )
        : await executeThroughSelectedEngine();

    const events = buildMatchingEventsFromSubmission({
      order,
      execution: engineResult.execution,
      engine: engineResult.engine,
      source: input.source,
      timeInForce: normalizedTimeInForce,
    });
    emitMatchingEvents(events);

    return {
      order,
      ledgerReservation,
      execution: engineResult.execution,
      orderReconciliation: engineResult.orderReconciliation,
      engine: engineResult.engine,
      source: input.source,
      timeInForce: normalizedTimeInForce,
      events,
    };
  });
}
"""))

index_text = index_path.read_text()
for export_line in [
    'export * from "./matching-events";',
]:
    if export_line not in index_text:
        index_text = index_text.rstrip() + "\n" + export_line + "\n"
index_path.write_text(index_text)

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent("""\
import { beforeEach, describe, expect, it, vi } from "vitest";

const { reserveOrderOnPlacement, selectMatchingEngine } = vi.hoisted(() => ({
  reserveOrderOnPlacement: vi.fn(),
  selectMatchingEngine: vi.fn(),
}));

vi.mock("../src/lib/ledger", () => ({
  reserveOrderOnPlacement,
}));
vi.mock("../src/lib/matching/select-engine", () => ({
  selectMatchingEngine,
}));

import { submitLimitOrder } from "../src/lib/matching/submit-limit-order";
import {
  buildMatchingEventsFromSubmission,
  listMatchingEvents,
  resetMatchingEventsForTests,
} from "../src/lib/matching/matching-events";
import { InMemoryOrderBook } from "../src/lib/matching/in-memory-order-book";

describe("matching events foundation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resetMatchingEventsForTests();
  });

  it("in-memory order book returns a websocket-ready book delta", () => {
    const book = new InMemoryOrderBook();
    const result = book.matchIncoming({
      orderId: "buy-1",
      symbol: "BTC-USD",
      side: "BUY",
      price: "100",
      qty: "2",
      timeInForce: "GTC",
    });

    expect(result.bookDelta).toEqual({
      symbol: "BTC-USD",
      bestBid: "100",
      bestAsk: null,
      bidDepth: "2",
      askDepth: "0",
      bidOrders: 1,
      askOrders: 0,
    });
  });

  it("buildMatchingEventsFromSubmission derives accepted, fill, filled, and book-delta events", () => {
    const events = buildMatchingEventsFromSubmission({
      order: {
        id: 101n,
        symbol: "BTC-USD",
        mode: "PAPER",
        side: "BUY",
        price: "100",
        qty: "1",
        status: "OPEN",
      },
      execution: {
        fills: [{ makerOrderId: "maker-1", takerOrderId: "101", qty: "1", price: "99" }],
        remainingQty: "0",
        tifAction: "FILLED",
        restingOrderId: null,
        bookDelta: {
          symbol: "BTC-USD",
          bestBid: null,
          bestAsk: "101",
          bidDepth: "0",
          askDepth: "3",
          bidOrders: 0,
          askOrders: 1,
        },
      },
      engine: "IN_MEMORY_MATCHER",
      source: "HUMAN",
      timeInForce: "IOC",
    });

    expect(events.map((e) => e.type)).toEqual([
      "ORDER_ACCEPTED",
      "ORDER_FILL",
      "ORDER_FILLED",
      "BOOK_DELTA",
    ]);
  });

  it("submitLimitOrder emits websocket-ready events through the shared boundary", async () => {
    reserveOrderOnPlacement.mockResolvedValue({ id: "reserve-1" });

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

    selectMatchingEngine.mockReturnValue({
      name: "IN_MEMORY_MATCHER",
      executeLimitOrder: vi.fn().mockResolvedValue({
        execution: {
          fills: [],
          remainingQty: "1",
          tifAction: "KEEP_OPEN",
          restingOrderId: "123",
          bookDelta: {
            symbol: "BTC-USD",
            bestBid: "100",
            bestAsk: null,
            bidDepth: "1",
            askDepth: "0",
            bidOrders: 1,
            askOrders: 0,
          },
        },
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

    expect(result.events.map((e: any) => e.type)).toEqual([
      "ORDER_ACCEPTED",
      "ORDER_RESTED",
      "BOOK_DELTA",
    ]);
    expect(listMatchingEvents().map((e) => e.type)).toEqual([
      "ORDER_ACCEPTED",
      "ORDER_RESTED",
      "BOOK_DELTA",
    ]);
  });
});
"""))

print("Patched package.json, added matching-events.ts, upgraded the in-memory book and engine to expose book deltas, patched submit-limit-order.ts to emit websocket-ready events, and wrote apps/api/test/matching-events.test.ts for Phase 4E.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4E patch applied."
