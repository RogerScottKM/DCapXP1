import { beforeEach, describe, expect, it } from "vitest";

import {
  assertSymbolEnabled,
  assertWithinPriceBand,
  consumeSlidingWindowLimit,
  enforceAdmissionControls,
  resetAdmissionControlCountersForTests,
} from "../src/lib/matching/admission-controls";

describe("admission controls", () => {
  beforeEach(() => {
    delete process.env.MATCH_DISABLED_SYMBOLS;
    delete process.env.MATCH_MAX_PRICE_DEVIATION_BPS;
    delete process.env.MATCH_MAX_ORDERS_PER_MINUTE_PER_USER;
    delete process.env.MATCH_MAX_ORDERS_PER_MINUTE_PER_SYMBOL;
    resetAdmissionControlCountersForTests();
  });

  it("rejects disabled symbols from either market.enabled or env kill switch", () => {
    expect(() =>
      assertSymbolEnabled({
        symbol: "BTC-USD",
        marketEnabled: false,
        disabledSymbols: [],
      }),
    ).toThrow(/Trading disabled/);

    expect(() =>
      assertSymbolEnabled({
        symbol: "ETH-USD",
        marketEnabled: true,
        disabledSymbols: ["ETH-USD"],
      }),
    ).toThrow(/Trading disabled/);
  });

  it("rejects prices outside the configured max deviation band", () => {
    expect(() =>
      assertWithinPriceBand({
        referencePrice: "100",
        submittedPrice: "110",
        maxDeviationBps: 500,
        symbol: "BTC-USD",
      }),
    ).toThrow(/Price band exceeded/);

    expect(() =>
      assertWithinPriceBand({
        referencePrice: "100",
        submittedPrice: "103",
        maxDeviationBps: 500,
        symbol: "BTC-USD",
      }),
    ).not.toThrow();
  });

  it("enforces per-user and per-symbol sliding-window rate limits", () => {
    consumeSlidingWindowLimit({
      key: "user:u1:BTC-USD:PAPER",
      limit: 2,
      nowMs: 1000,
      windowMs: 60000,
    });
    consumeSlidingWindowLimit({
      key: "user:u1:BTC-USD:PAPER",
      limit: 2,
      nowMs: 1001,
      windowMs: 60000,
    });

    expect(() =>
      consumeSlidingWindowLimit({
        key: "user:u1:BTC-USD:PAPER",
        limit: 2,
        nowMs: 1002,
        windowMs: 60000,
      }),
    ).toThrow(/Rate limit exceeded/);
  });

  it("enforceAdmissionControls consults latest trade, kill switch, and both rate windows", async () => {
    process.env.MATCH_MAX_PRICE_DEVIATION_BPS = "500";
    process.env.MATCH_MAX_ORDERS_PER_MINUTE_PER_USER = "2";
    process.env.MATCH_MAX_ORDERS_PER_MINUTE_PER_SYMBOL = "3";

    const db = {
      market: {
        findUnique: async ({ where }: any) => ({ symbol: where.symbol, enabled: true }),
      },
      trade: {
        findFirst: async () => ({ id: 55n, price: "100" }),
      },
    };

    await enforceAdmissionControls({
      db,
      userId: "user-1",
      symbol: "BTC-USD",
      mode: "PAPER",
      price: "103",
    });

    await enforceAdmissionControls({
      db,
      userId: "user-1",
      symbol: "BTC-USD",
      mode: "PAPER",
      price: "104",
    });

    await expect(
      enforceAdmissionControls({
        db,
        userId: "user-1",
        symbol: "BTC-USD",
        mode: "PAPER",
        price: "104",
      }),
    ).rejects.toThrow(/Rate limit exceeded/);
  });
});
