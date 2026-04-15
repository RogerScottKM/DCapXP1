import { beforeEach, describe, expect, it, vi } from "vitest";

const { prismaMock, recordSecurityAudit } = vi.hoisted(() => ({
  prismaMock: {
    $queryRaw: vi.fn(),
    trade: { findMany: vi.fn(), aggregate: vi.fn() },
    ledgerTransaction: { findMany: vi.fn() },
    order: { findMany: vi.fn() },
  },
  recordSecurityAudit: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));

import { runReconciliation } from "../src/workers/reconciliation";

describe("reconciliation worker", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("passes all checks on a healthy empty ledger", async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([]);
    prismaMock.$queryRaw.mockResolvedValueOnce([]);
    prismaMock.trade.findMany.mockResolvedValue([]);
    prismaMock.order.findMany.mockResolvedValue([]);

    const results = await runReconciliation();

    const failures = results.filter((r) => !r.ok);
    expect(failures).toHaveLength(0);
    expect(recordSecurityAudit).not.toHaveBeenCalled();
  });

  it("detects global balance mismatch and logs audit event", async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([
      { assetCode: "USD", total_debit: "1005.00", total_credit: "1000.00" },
    ]);
    prismaMock.$queryRaw.mockResolvedValueOnce([]);
    prismaMock.trade.findMany.mockResolvedValue([]);
    prismaMock.order.findMany.mockResolvedValue([]);

    const results = await runReconciliation();

    const failures = results.filter((r) => !r.ok);
    expect(failures.length).toBeGreaterThanOrEqual(1);
    expect(failures[0].check).toContain("GLOBAL_BALANCE");

    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "RECONCILIATION_FAILURE",
        resourceType: "LEDGER",
      }),
    );
  });

  it("detects negative account balances", async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([
      { assetCode: "USD", total_debit: "1000.00", total_credit: "1000.00" },
    ]);
    prismaMock.$queryRaw.mockResolvedValueOnce([
      {
        accountId: "acct-1",
        ownerType: "USER",
        ownerRef: "user-1",
        assetCode: "USD",
        accountType: "USER_AVAILABLE",
        net_balance: "-50.00",
      },
    ]);
    prismaMock.trade.findMany.mockResolvedValue([]);
    prismaMock.order.findMany.mockResolvedValue([]);

    const results = await runReconciliation();

    const negativeCheck = results.find((r) => r.check.startsWith("NEGATIVE_BALANCE"));
    expect(negativeCheck).toBeDefined();
    expect(negativeCheck!.ok).toBe(false);
  });

  it("detects missing trade settlements", async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([
      { assetCode: "USD", total_debit: "500", total_credit: "500" },
    ]);
    prismaMock.$queryRaw.mockResolvedValueOnce([]);
    prismaMock.trade.findMany.mockResolvedValue([
      { id: 1n, createdAt: new Date() },
      { id: 2n, createdAt: new Date() },
    ]);
    prismaMock.ledgerTransaction.findMany.mockResolvedValue([
      { referenceId: "1:FILL_SETTLEMENT" },
    ]);
    prismaMock.order.findMany.mockResolvedValue([]);

    const results = await runReconciliation();

    const tradeCheck = results.find((r) => r.check === "RECENT_TRADE_SETTLEMENT");
    expect(tradeCheck).toBeDefined();
    expect(tradeCheck!.ok).toBe(false);
    expect((tradeCheck!.details as any).missingSettlements).toBe(1);
  });
});
