import { beforeEach, describe, expect, it, vi } from "vitest";
import { Decimal } from "@prisma/client/runtime/library";

const { prismaMock } = vi.hoisted(() => ({
  prismaMock: {
    order: {
      findUniqueOrThrow: vi.fn(),
    },
    trade: {
      aggregate: vi.fn(),
    },
  },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

import { InMemoryOrderBook } from "../src/lib/matching/in-memory-order-book";
import { InMemoryMatchingEngine } from "../src/lib/matching/in-memory-matching-engine";
import { dbMatchingEngine } from "../src/lib/matching/db-matching-engine";
import { selectMatchingEngine } from "../src/lib/matching/select-engine";

describe("in-memory matching engine foundation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.MATCHING_ENGINE;
  });

  it("matches BUY takers against the best asks using price-time priority", () => {
    const book = new InMemoryOrderBook();
    book.add({
      orderId: "ask-2",
      symbol: "BTC-USD",
      side: "SELL",
      price: "99",
      remainingQty: "2",
      createdAt: new Date("2026-01-01T00:10:00Z"),
      timeInForce: "GTC",
    });
    book.add({
      orderId: "ask-1",
      symbol: "BTC-USD",
      side: "SELL",
      price: "99",
      remainingQty: "3",
      createdAt: new Date("2026-01-01T00:00:00Z"),
      timeInForce: "GTC",
    });
    book.add({
      orderId: "ask-3",
      symbol: "BTC-USD",
      side: "SELL",
      price: "100",
      remainingQty: "5",
      createdAt: new Date("2026-01-01T00:00:00Z"),
      timeInForce: "GTC",
    });

    const result = book.matchIncoming({
      orderId: "buy-1",
      symbol: "BTC-USD",
      side: "BUY",
      price: "100",
      qty: "6",
      timeInForce: "GTC",
      createdAt: new Date("2026-01-01T01:00:00Z"),
    });

    expect(result.fills.map((f) => f.makerOrderId)).toEqual(["ask-1", "ask-2", "ask-3"]);
    expect(result.fills.map((f) => f.qty)).toEqual(["3", "2", "1"]);
    expect(result.remainingQty).toBe("0");
    expect(result.tifAction).toBe("FILLED");
  });

  it("rests remaining GTC quantity on the book but cancels IOC remainder", () => {
    const gtcBook = new InMemoryOrderBook();
    const gtcResult = gtcBook.matchIncoming({
      orderId: "buy-gtc",
      symbol: "BTC-USD",
      side: "BUY",
      price: "100",
      qty: "5",
      timeInForce: "GTC",
      createdAt: new Date("2026-01-01T01:00:00Z"),
    });

    expect(gtcResult.remainingQty).toBe("5");
    expect(gtcResult.tifAction).toBe("KEEP_OPEN");
    expect(gtcBook.snapshot("BUY")).toHaveLength(1);

    const iocBook = new InMemoryOrderBook();
    const iocResult = iocBook.matchIncoming({
      orderId: "buy-ioc",
      symbol: "BTC-USD",
      side: "BUY",
      price: "100",
      qty: "5",
      timeInForce: "IOC",
      createdAt: new Date("2026-01-01T01:00:00Z"),
    });

    expect(iocResult.remainingQty).toBe("5");
    expect(iocResult.tifAction).toBe("CANCEL_REMAINDER");
    expect(iocBook.snapshot("BUY")).toHaveLength(0);
  });

  it("selectMatchingEngine defaults to DB and can explicitly choose in-memory", () => {
    expect(selectMatchingEngine()).toBe(dbMatchingEngine);
    expect(selectMatchingEngine("in_memory").name).toBe("IN_MEMORY_MATCHER");

    process.env.MATCHING_ENGINE = "IN_MEMORY_MATCHER";
    expect(selectMatchingEngine().name).toBe("IN_MEMORY_MATCHER");
  });

  it("in-memory engine stages and matches orders across successive submissions", async () => {
    const sellOrder = {
      id: 1n,
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
      .mockResolvedValueOnce(buyOrder);

    prismaMock.trade.aggregate
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } });

    const engine = new InMemoryMatchingEngine();

    const first = await engine.executeLimitOrder({ orderId: sellOrder.id }, prismaMock as any);
    const second = await engine.executeLimitOrder({ orderId: buyOrder.id }, prismaMock as any);

    expect(first.engine).toBe("IN_MEMORY_MATCHER");
    expect((first.execution as any).restingOrderId).toBe("1");
    expect((second.execution as any).fills).toHaveLength(1);
    expect((second.execution as any).fills[0]).toEqual(
      expect.objectContaining({ makerOrderId: "1", qty: "2", price: "99" }),
    );
  });
});
