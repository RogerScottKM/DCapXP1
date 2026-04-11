import { Decimal } from "@prisma/client/runtime/library";
import { describe, expect, it } from "vitest";

import { assertTradeSettlementConsistency } from "../src/lib/ledger/reconciliation";

describe("ledger trade settlement reconciliation", () => {
  it("accepts a consistent trade settlement record", () => {
    const result = assertTradeSettlementConsistency({
      trade: {
        id: 101n,
        symbol: "BTC-USD",
        qty: new Decimal("0.5"),
        price: new Decimal("60000"),
        mode: "PAPER",
        buyOrderId: 11n,
        sellOrderId: 22n,
      },
      ledgerTransaction: {
        referenceType: "ORDER_EVENT",
        referenceId: "101:FILL_SETTLEMENT",
        metadata: {
          tradeRef: "101",
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
    expect(result.referenceId).toBe("101:FILL_SETTLEMENT");
    expect(result.postingCount).toBe(5);
  });

  it("rejects mismatched settlement metadata", () => {
    expect(() =>
      assertTradeSettlementConsistency({
        trade: {
          id: 101n,
          symbol: "BTC-USD",
          qty: new Decimal("0.5"),
          price: new Decimal("60000"),
          mode: "PAPER",
          buyOrderId: 11n,
          sellOrderId: 22n,
        },
        ledgerTransaction: {
          referenceType: "ORDER_EVENT",
          referenceId: "101:FILL_SETTLEMENT",
          metadata: {
            tradeRef: "101",
            buyOrderId: "11",
            sellOrderId: "22",
            symbol: "ETH-USD",
            qty: "0.5",
            price: "60000",
            mode: "PAPER",
          },
          postings: [
            { assetCode: "USD", amount: "30000", side: "DEBIT" },
            { assetCode: "USD", amount: "30000", side: "CREDIT" },
            { assetCode: "BTC", amount: "0.5", side: "DEBIT" },
            { assetCode: "BTC", amount: "0.5", side: "CREDIT" },
          ],
        },
      }),
    ).toThrow(/metadata.symbol/i);
  });

  it("rejects ledger transactions without enough postings", () => {
    expect(() =>
      assertTradeSettlementConsistency({
        trade: {
          id: 101n,
          symbol: "BTC-USD",
          qty: new Decimal("0.5"),
          price: new Decimal("60000"),
          mode: "PAPER",
          buyOrderId: 11n,
          sellOrderId: 22n,
        },
        ledgerTransaction: {
          referenceType: "ORDER_EVENT",
          referenceId: "101:FILL_SETTLEMENT",
          metadata: {
            tradeRef: "101",
            buyOrderId: "11",
            sellOrderId: "22",
            symbol: "BTC-USD",
            qty: "0.5",
            price: "60000",
            mode: "PAPER",
          },
          postings: [
            { assetCode: "USD", amount: "30000", side: "DEBIT" },
          ],
        },
      }),
    ).toThrow(/must contain postings/i);
  });
});
