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
