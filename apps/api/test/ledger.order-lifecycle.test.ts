import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  ensureUserLedgerAccounts,
  ensureSystemLedgerAccounts,
  postLedgerTransaction,
} = vi.hoisted(() => ({
  prismaMock: {
    market: { findUnique: vi.fn() },
    ledgerPosting: { findMany: vi.fn() },
    ledgerTransaction: { findFirst: vi.fn() },
    order: { findUnique: vi.fn() },
  },
  ensureUserLedgerAccounts: vi.fn(),
  ensureSystemLedgerAccounts: vi.fn(),
  postLedgerTransaction: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/ledger/accounts", () => ({
  ensureUserLedgerAccounts,
  ensureSystemLedgerAccounts,
}));
vi.mock("../src/lib/ledger/service", () => ({ postLedgerTransaction }));

import { Decimal } from "@prisma/client/runtime/library";
import { reserveOrderOnPlacement, releaseOrderOnCancel, settleMatchedTrade } from "../src/lib/ledger/order-lifecycle";

describe("ledger order lifecycle", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.market.findUnique.mockResolvedValue({ symbol: "BTC-USD", baseAsset: "BTC", quoteAsset: "USD" });
    prismaMock.ledgerTransaction.findFirst.mockResolvedValue(null);
    prismaMock.ledgerPosting.findMany.mockResolvedValue([{ side: "CREDIT", amount: "100000.00" }]);
    ensureUserLedgerAccounts.mockResolvedValue({ available: { id: "acct-available" }, held: { id: "acct-held" } });
    ensureSystemLedgerAccounts.mockResolvedValue({ feeRevenue: { id: "fee-revenue" } });
    postLedgerTransaction.mockResolvedValue({ id: "ltx-1" });
  });

  it("reserves quote asset from available to held for BUY limit orders", async () => {
    await reserveOrderOnPlacement({
      orderId: "101",
      userId: "user-1",
      symbol: "BTC-USD",
      side: "BUY",
      qty: "2",
      price: "100",
      mode: "PAPER",
    });

    expect(postLedgerTransaction).toHaveBeenCalledWith(
      expect.objectContaining({
        referenceId: "101:PLACE_HOLD",
        postings: [
          expect.objectContaining({ accountId: "acct-available", assetCode: "USD", side: "DEBIT", amount: new Decimal("200") }),
          expect.objectContaining({ accountId: "acct-held", assetCode: "USD", side: "CREDIT", amount: new Decimal("200") }),
        ],
      }),
      expect.anything(),
    );
  });

  it("releases held funds back to available on cancellation", async () => {
    await releaseOrderOnCancel({
      orderId: "101",
      userId: "user-1",
      symbol: "BTC-USD",
      side: "BUY",
      qty: "2",
      price: "100",
      mode: "PAPER",
    });

    expect(postLedgerTransaction).toHaveBeenCalledWith(
      expect.objectContaining({
        referenceId: "101:CANCEL_RELEASE",
        postings: [
          expect.objectContaining({ accountId: "acct-held", assetCode: "USD", side: "DEBIT", amount: new Decimal("200") }),
          expect.objectContaining({ accountId: "acct-available", assetCode: "USD", side: "CREDIT", amount: new Decimal("200") }),
        ],
      }),
      expect.anything(),
    );
  });

  it("settles matched trades between counterparties plus fee revenue", async () => {
    prismaMock.order.findUnique
      .mockResolvedValueOnce({ id: 1n, userId: "buyer-1", symbol: "BTC-USD", side: "BUY", qty: new Decimal("2"), price: new Decimal("100"), mode: "PAPER", status: "OPEN" })
      .mockResolvedValueOnce({ id: 2n, userId: "seller-1", symbol: "BTC-USD", side: "SELL", qty: new Decimal("2"), price: new Decimal("100"), mode: "PAPER", status: "OPEN" });

    ensureUserLedgerAccounts
      .mockResolvedValueOnce({ available: { id: "buyer-base-available" }, held: { id: "buyer-base-held" } })
      .mockResolvedValueOnce({ available: { id: "buyer-quote-available" }, held: { id: "buyer-quote-held" } })
      .mockResolvedValueOnce({ available: { id: "seller-base-available" }, held: { id: "seller-base-held" } })
      .mockResolvedValueOnce({ available: { id: "seller-quote-available" }, held: { id: "seller-quote-held" } });

    prismaMock.ledgerPosting.findMany
      .mockResolvedValueOnce([{ side: "CREDIT", amount: "500.00" }])
      .mockResolvedValueOnce([{ side: "CREDIT", amount: "5.00" }]);

    await settleMatchedTrade({
      tradeRef: "trade-1",
      buyOrderId: "1",
      sellOrderId: "2",
      symbol: "BTC-USD",
      qty: "2",
      price: "100",
      mode: "PAPER",
      quoteFee: "5",
    });

    expect(postLedgerTransaction).toHaveBeenCalledWith(
      expect.objectContaining({
        referenceId: "trade-1:FILL_SETTLEMENT",
        postings: [
          expect.objectContaining({ accountId: "buyer-quote-held", assetCode: "USD", side: "DEBIT", amount: new Decimal("200") }),
          expect.objectContaining({ accountId: "seller-quote-available", assetCode: "USD", side: "CREDIT", amount: new Decimal("195") }),
          expect.objectContaining({ accountId: "fee-revenue", assetCode: "USD", side: "CREDIT", amount: new Decimal("5") }),
          expect.objectContaining({ accountId: "seller-base-held", assetCode: "BTC", side: "DEBIT", amount: new Decimal("2") }),
          expect.objectContaining({ accountId: "buyer-base-available", assetCode: "BTC", side: "CREDIT", amount: new Decimal("2") }),
        ],
      }),
      expect.anything(),
    );
  });
});
