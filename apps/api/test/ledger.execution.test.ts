import { describe, expect, it } from "vitest";

import {
  computeBuyPriceImprovementReleaseAmount,
  computeQuoteFeeAmount,
  isCrossingLimitOrder,
} from "../src/lib/ledger/execution";

describe("ledger execution helper", () => {
  it("detects crossing prices for buy and sell limit orders", () => {
    expect(isCrossingLimitOrder("BUY", "100", "99")).toBe(true);
    expect(isCrossingLimitOrder("BUY", "100", "101")).toBe(false);
    expect(isCrossingLimitOrder("SELL", "100", "101")).toBe(true);
    expect(isCrossingLimitOrder("SELL", "100", "99")).toBe(false);
  });

  it("computes quote fees from bps", () => {
    expect(computeQuoteFeeAmount("1000", "25").toString()).toBe("2.5");
    expect(computeQuoteFeeAmount("1000", "0").toString()).toBe("0");
  });

  it("computes buy-side price improvement release amount", () => {
    expect(computeBuyPriceImprovementReleaseAmount("100", "90", "5").toString()).toBe("50");
    expect(computeBuyPriceImprovementReleaseAmount("100", "100", "5").toString()).toBe("0");
  });
});
