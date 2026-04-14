import { Decimal } from "@prisma/client/runtime/library";
import { describe, expect, it } from "vitest";

import {
  assertTradeSettlementConsistency,
} from "../src/lib/ledger/reconciliation";
import {
  assertCumulativeFillWithinOrder,
  computeBuyHeldQuoteRelease,
  computeExecutedQuote,
  computeReservedQuote,
} from "../src/lib/ledger/hold-release";
import {
  computeBuyPriceImprovementReleaseAmount,
  computeQuoteFeeAmount,
} from "../src/lib/ledger/execution";
import {
  computeRemainingQty,
  deriveOrderStatus,
  isFullyFilled,
} from "../src/lib/ledger/order-state";

describe("ledger phase2 smoke", () => {
  it("models reserve to partial fill under current persisted status semantics", () => {
    const reservedQuote = computeReservedQuote("10", "100");
    const firstFillQuote = computeExecutedQuote("4", "99");
    const remainingQty = computeRemainingQty("10", "4");
    const expectedStatus = deriveOrderStatus("OPEN", "10", "4");
    const quoteFee = computeQuoteFeeAmount(firstFillQuote, "25");

    expect(reservedQuote.toString()).toBe("1000");
    expect(firstFillQuote.toString()).toBe("396");
    expect(remainingQty.toString()).toBe("6");
    expect(isFullyFilled("10", "4")).toBe(false);

    // Phase 2G stays aligned to the current persisted enum semantics:
    // partial fills still reconcile to OPEN until the later enum expansion.
    expect(expectedStatus).toBe("OPEN");
    expect(quoteFee.toString()).toBe("0.99");
  });

  it("models final buy completion with residual hold release and price improvement release", () => {
    const fullyExecutedQuote = computeExecutedQuote("10", "99");
    const residualHeldRelease = computeBuyHeldQuoteRelease({
      orderQty: "10",
      limitPrice: "100",
      cumulativeFilledQty: "10",
      weightedExecutedQuote: fullyExecutedQuote,
    });
    const priceImprovementRelease = computeBuyPriceImprovementReleaseAmount("100", "99", "10");
    const finalStatus = deriveOrderStatus("OPEN", "10", "10");

    expect(fullyExecutedQuote.toString()).toBe("990");
    expect(residualHeldRelease.toString()).toBe("10");
    expect(priceImprovementRelease.toString()).toBe("10");
    expect(finalStatus).toBe("FILLED");

    expect(() =>
      assertCumulativeFillWithinOrder(new Decimal("10"), new Decimal("10")),
    ).not.toThrow();
    expect(isFullyFilled("10", "10")).toBe(true);
  });

  it("accepts a synthetic fill settlement reconciliation record", () => {
    const result = assertTradeSettlementConsistency({
      trade: {
        id: 501n,
        symbol: "BTC-USD",
        qty: new Decimal("0.5"),
        price: new Decimal("60000"),
        mode: "PAPER",
        buyOrderId: 11n,
        sellOrderId: 22n,
      },
      ledgerTransaction: {
        referenceType: "ORDER_EVENT",
        referenceId: "501:FILL_SETTLEMENT",
        metadata: {
          tradeRef: "501",
          buyOrderId: "11",
          sellOrderId: "22",
          symbol: "BTC-USD",
          qty: "0.5",
          price: "60000",
          mode: "PAPER",
        },
        postings: [
          { assetCode: "USD", amount: "30000", side: "DEBIT" },
          { assetCode: "USD", amount: "29990", side: "CREDIT" },
          { assetCode: "USD", amount: "10", side: "CREDIT" },
          { assetCode: "BTC", amount: "0.5", side: "DEBIT" },
          { assetCode: "BTC", amount: "0.5", side: "CREDIT" },
        ],
      },
    });

    expect(result.ok).toBe(true);
    expect(result.referenceId).toBe("501:FILL_SETTLEMENT");
    expect(result.postingCount).toBe(5);
  });
});
