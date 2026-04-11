import { describe, expect, it } from "vitest";

import { assertBalancedPostings, buildLedgerTransfer } from "../src/lib/ledger/posting";

describe("ledger posting invariants", () => {
  it("accepts balanced postings", () => {
    const postings = assertBalancedPostings([
      { accountId: "a1", assetCode: "USD", side: "DEBIT", amount: "100.00" },
      { accountId: "a2", assetCode: "USD", side: "CREDIT", amount: "100.00" },
    ]);

    expect(postings).toHaveLength(2);
    expect(postings[0].assetCode).toBe("USD");
  });

  it("rejects unbalanced postings", () => {
    expect(() =>
      assertBalancedPostings([
        { accountId: "a1", assetCode: "USD", side: "DEBIT", amount: "100.00" },
        { accountId: "a2", assetCode: "USD", side: "CREDIT", amount: "90.00" },
      ]),
    ).toThrow(/not balanced/i);
  });

  it("buildLedgerTransfer creates a balanced transfer pair", () => {
    const transfer = buildLedgerTransfer({
      fromAccountId: "held-usd",
      toAccountId: "available-usd",
      assetCode: "USD",
      amount: "25.5",
    });

    const normalized = assertBalancedPostings(transfer);
    expect(normalized).toHaveLength(2);
    expect(normalized[0].side).toBe("CREDIT");
    expect(normalized[1].side).toBe("DEBIT");
  });
});
