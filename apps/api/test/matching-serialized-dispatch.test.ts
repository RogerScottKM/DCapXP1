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

import {
  buildSymbolModeKey,
  getSerializedLaneCount,
  resetSerializedDispatchForTests,
  runSerializedByKey,
} from "../src/lib/matching/serialized-dispatch";
import { submitLimitOrder } from "../src/lib/matching/submit-limit-order";

describe("matching serialized dispatch", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resetSerializedDispatchForTests();
  });

  it("serializes tasks for the same symbol:mode key", async () => {
    const events: string[] = [];

    const first = runSerializedByKey("BTC-USD:PAPER", async () => {
      events.push("first:start");
      await new Promise((resolve) => setTimeout(resolve, 20));
      events.push("first:end");
      return "first";
    });

    const second = runSerializedByKey("BTC-USD:PAPER", async () => {
      events.push("second:start");
      events.push("second:end");
      return "second";
    });

    const result = await Promise.all([first, second]);

    expect(result).toEqual(["first", "second"]);
    expect(events).toEqual(["first:start", "first:end", "second:start", "second:end"]);
  });

  it("allows different symbol:mode keys to progress independently", async () => {
    const events: string[] = [];

    const first = runSerializedByKey("BTC-USD:PAPER", async () => {
      events.push("btc:start");
      await new Promise((resolve) => setTimeout(resolve, 20));
      events.push("btc:end");
      return "btc";
    });

    const second = runSerializedByKey("ETH-USD:PAPER", async () => {
      events.push("eth:start");
      events.push("eth:end");
      return "eth";
    });

    const result = await Promise.all([first, second]);

    expect(result.sort()).toEqual(["btc", "eth"]);
    expect(events[0]).toBe("btc:start");
    expect(events).toContain("eth:start");
    expect(events).toContain("eth:end");
  });

  it("submitLimitOrder serializes only the in-memory engine path by symbol:mode", async () => {
    reserveOrderOnPlacement.mockResolvedValue({ id: "reserve-1" });

    const tx = {
      order: {
        create: vi
          .fn()
          .mockResolvedValueOnce({
            id: 101n,
            symbol: "BTC-USD",
            side: "BUY",
            price: "100",
            qty: "1",
            status: "OPEN",
            timeInForce: "GTC",
            mode: "PAPER",
            userId: "user-1",
          })
          .mockResolvedValueOnce({
            id: 102n,
            symbol: "BTC-USD",
            side: "BUY",
            price: "100",
            qty: "1",
            status: "OPEN",
            timeInForce: "GTC",
            mode: "PAPER",
            userId: "user-2",
          }),
      },
    };

    const fakeDb = {
      $transaction: vi.fn(async (fn: any) => fn(tx)),
    };

    const events: string[] = [];
    const engine = {
      name: "IN_MEMORY_MATCHER",
      executeLimitOrder: vi
        .fn()
        .mockImplementationOnce(async () => {
          events.push("first:start");
          await new Promise((resolve) => setTimeout(resolve, 20));
          events.push("first:end");
          return {
            execution: { fills: [], remainingQty: "1", tifAction: "KEEP_OPEN", restingOrderId: "101" },
            orderReconciliation: { ok: true },
            engine: "IN_MEMORY_MATCHER",
          };
        })
        .mockImplementationOnce(async () => {
          events.push("second:start");
          events.push("second:end");
          return {
            execution: { fills: [], remainingQty: "1", tifAction: "KEEP_OPEN", restingOrderId: "102" },
            orderReconciliation: { ok: true },
            engine: "IN_MEMORY_MATCHER",
          };
        }),
    };

    selectMatchingEngine.mockReturnValue(engine);

    const first = submitLimitOrder(
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

    const second = submitLimitOrder(
      {
        userId: "user-2",
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

    await Promise.all([first, second]);

    expect(selectMatchingEngine).toHaveBeenCalledTimes(2);
    expect(events).toEqual(["first:start", "first:end", "second:start", "second:end"]);
    expect(getSerializedLaneCount()).toBe(0);
  });

  it("buildSymbolModeKey uses symbol and mode deterministically", () => {
    expect(buildSymbolModeKey("BTC-USD", "PAPER")).toBe("BTC-USD:PAPER");
  });
});
