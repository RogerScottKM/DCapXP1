import { describe, expect, it } from "vitest";
import { Decimal } from "@prisma/client/runtime/library";
import {
  computeBuyHeldQuoteRelease,
  computeExecutedQuote,
  assertCumulativeFillWithinOrder,
  computeRemainingQtyFromCumulative,
} from "../src/lib/ledger/hold-release";

describe("ledger hold-release helpers", () => {
  it("computes residual buy hold release on final completion", () => {
    const spent = computeExecutedQuote("10", "99");
    const release = computeBuyHeldQuoteRelease({
      orderQty: "10",
      limitPrice: "100",
      cumulativeFilledQty: "10",
      weightedExecutedQuote: spent,
    });
    expect(release.toString()).toBe("10");
  });

  it("returns zero release when order still has remaining quantity", () => {
    const spent = computeExecutedQuote("4", "99");
    const release = computeBuyHeldQuoteRelease({
      orderQty: "10",
      limitPrice: "100",
      cumulativeFilledQty: "4",
      weightedExecutedQuote: spent,
    });
    expect(release.toString()).toBe("0");
    expect(computeRemainingQtyFromCumulative("10", "4").toString()).toBe("6");
  });

  it("guards cumulative fills from exceeding order quantity", () => {
    expect(() => assertCumulativeFillWithinOrder(new Decimal("10"), new Decimal("11"))).toThrow(/cannot exceed/i);
  });
});
