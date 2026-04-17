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
  .mockResolvedValueOnce(new Decimal("3")) // first execute: sell order initial remaining
  .mockResolvedValueOnce(new Decimal("3")) // first execute: sell order final refresh remaining
  .mockResolvedValueOnce(new Decimal("2")) // second execute: buy order initial remaining
  .mockResolvedValueOnce(new Decimal("0")); // second execute: buy order final refresh remaining after full fill

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
