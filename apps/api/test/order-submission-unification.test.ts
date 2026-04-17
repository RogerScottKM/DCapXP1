import { beforeEach, describe, expect, it, vi } from "vitest";

const { reserveOrderOnPlacement, executeLimitOrderAgainstBook, reconcileOrderExecution } = vi.hoisted(() => ({
  reserveOrderOnPlacement: vi.fn(),
  executeLimitOrderAgainstBook: vi.fn(),
  reconcileOrderExecution: vi.fn(),
}));

vi.mock("../src/lib/ledger", () => ({
  reserveOrderOnPlacement,
  executeLimitOrderAgainstBook,
  reconcileOrderExecution,
}));

import { DbMatchingEngine } from "../src/lib/matching/db-matching-engine";
import { submitLimitOrder } from "../src/lib/matching/submit-limit-order";

describe("order submission unification", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("db matching engine delegates to execution and reconciliation helpers", async () => {
    executeLimitOrderAgainstBook.mockResolvedValue({ order: { id: 10n }, fills: [], remainingQty: "0" });
    reconcileOrderExecution.mockResolvedValue({ orderId: "10", ok: true });

    const engine = new DbMatchingEngine();
    const result = await engine.executeLimitOrder({ orderId: 10n, quoteFeeBps: "5" }, {} as any);

    expect(executeLimitOrderAgainstBook).toHaveBeenCalledWith(
      { orderId: 10n, quoteFeeBps: "5" },
      {} as any,
    );
    expect(reconcileOrderExecution).toHaveBeenCalledWith(10n, {} as any);
    expect(result.engine).toBe("DB_MATCHER");
  });

  it("submitLimitOrder creates, reserves, and dispatches through the shared engine boundary", async () => {
    const tx = {
      order: {
        create: vi.fn().mockResolvedValue({
          id: 101n,
          symbol: "BTC-USD",
          side: "BUY",
          price: "100",
          qty: "1",
          status: "OPEN",
          timeInForce: "IOC",
          mode: "PAPER",
          userId: "user-1",
        }),
      },
    };

    const fakeDb = {
      $transaction: vi.fn(async (fn: any) => fn(tx)),
    };

    reserveOrderOnPlacement.mockResolvedValue({ id: "reserve-1" });

    const engine = {
      name: "DB_MATCHER",
      executeLimitOrder: vi.fn().mockResolvedValue({
        execution: { order: { id: 101n }, fills: [], remainingQty: "0" },
        orderReconciliation: { orderId: "101", ok: true },
        engine: "DB_MATCHER",
      }),
    };

    const result = await submitLimitOrder(
      {
        userId: "user-1",
        symbol: "BTC-USD",
        side: "BUY",
        price: "100",
        qty: "1",
        mode: "PAPER" as any,
        quoteFeeBps: "5",
        timeInForce: "IOC",
        source: "HUMAN",
      },
      fakeDb as any,
      engine as any,
    );

    expect(fakeDb.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.order.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        symbol: "BTC-USD",
        side: "BUY",
        userId: "user-1",
        status: "OPEN",
        timeInForce: "IOC",
      }),
    });
    expect(reserveOrderOnPlacement).toHaveBeenCalledWith(
      expect.objectContaining({
        orderId: 101n,
        userId: "user-1",
        symbol: "BTC-USD",
      }),
      tx,
    );
    expect(engine.executeLimitOrder).toHaveBeenCalledWith(
      { orderId: 101n, quoteFeeBps: "5" },
      tx,
    );
    expect(result.engine).toBe("DB_MATCHER");
    expect(result.source).toBe("HUMAN");
    expect(result.timeInForce).toBe("IOC");
  });
});
