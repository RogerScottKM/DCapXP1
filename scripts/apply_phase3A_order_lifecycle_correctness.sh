#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
execution_path = root / "apps/api/src/lib/ledger/execution.ts"
test_path = root / "apps/api/test/ledger.lifecycle.test.ts"

if not pkg_path.exists():
    raise SystemExit(f"Missing package.json: {pkg_path}")
if not execution_path.exists():
    raise SystemExit(f"Missing execution.ts: {execution_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:ledger:lifecycle"] = "vitest run test/ledger.lifecycle.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

execution_text = execution_path.read_text()

pattern = re.compile(
    r'(where:\s*\{\s*symbol:\s*order\.symbol,\s*mode:\s*order\.mode,\s*)status:\s*"OPEN"(,\s*side:\s*oppositeSide,)',
    re.DOTALL,
)
new_execution_text, count = pattern.subn(
    r'\1status: { in: ["OPEN", "PARTIALLY_FILLED"] }\2',
    execution_text,
    count=1,
)
if count == 0 and 'status: { in: ["OPEN", "PARTIALLY_FILLED"] }' not in execution_text:
    raise SystemExit("Could not patch getMatchingOrders() to include PARTIALLY_FILLED makers.")
execution_path.write_text(new_execution_text if count else execution_text)

test_text = dedent('''import { Decimal } from "@prisma/client/runtime/library";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  ensureUserLedgerAccounts,
  settleMatchedTrade,
  reconcileTradeSettlement,
  postLedgerTransaction,
  assertCumulativeFillWithinOrder,
  computeBuyHeldQuoteRelease,
} = vi.hoisted(() => ({
  prismaMock: {
    trade: {
      aggregate: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
    },
    order: {
      findUniqueOrThrow: vi.fn(),
      findMany: vi.fn(),
      update: vi.fn(),
    },
    ledgerTransaction: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
    },
  },
  ensureUserLedgerAccounts: vi.fn(),
  settleMatchedTrade: vi.fn(),
  reconcileTradeSettlement: vi.fn(),
  postLedgerTransaction: vi.fn(),
  assertCumulativeFillWithinOrder: vi.fn(),
  computeBuyHeldQuoteRelease: vi.fn(() => new Decimal("0")),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/ledger/accounts", () => ({ ensureUserLedgerAccounts }));
vi.mock("../src/lib/ledger/order-lifecycle", () => ({ settleMatchedTrade }));
vi.mock("../src/lib/ledger/reconciliation", async () => {
  const actual = await vi.importActual("../src/lib/ledger/reconciliation");
  return {
    ...actual,
    reconcileTradeSettlement,
  };
});
vi.mock("../src/lib/ledger/service", () => ({ postLedgerTransaction }));
vi.mock("../src/lib/ledger/hold-release", async () => {
  const actual = await vi.importActual("../src/lib/ledger/hold-release");
  return {
    ...actual,
    assertCumulativeFillWithinOrder,
    computeBuyHeldQuoteRelease,
  };
});

import {
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
} from "../src/lib/ledger/execution";

describe("ledger lifecycle", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("syncOrderStatusFromTrades updates OPEN to PARTIALLY_FILLED after a partial execution", async () => {
    prismaMock.order.findUniqueOrThrow.mockResolvedValue({
      id: 1n,
      qty: new Decimal("10"),
      status: "OPEN",
    });
    prismaMock.trade.aggregate
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("4") } })
      .mockResolvedValueOnce({ _sum: { qty: null } });
    prismaMock.order.update.mockResolvedValue({
      id: 1n,
      status: "PARTIALLY_FILLED",
    });

    const result = await syncOrderStatusFromTrades(1n, prismaMock as any);

    expect(prismaMock.order.update).toHaveBeenCalledWith({
      where: { id: 1n },
      data: { status: "PARTIALLY_FILLED" },
    });
    expect(result.status).toBe("PARTIALLY_FILLED");
  });

  it("syncOrderStatusFromTrades updates to FILLED when cumulative execution reaches order quantity", async () => {
    prismaMock.order.findUniqueOrThrow.mockResolvedValue({
      id: 2n,
      qty: new Decimal("10"),
      status: "PARTIALLY_FILLED",
    });
    prismaMock.trade.aggregate
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("10") } })
      .mockResolvedValueOnce({ _sum: { qty: null } });
    prismaMock.order.update.mockResolvedValue({
      id: 2n,
      status: "FILLED",
    });

    const result = await syncOrderStatusFromTrades(2n, prismaMock as any);

    expect(prismaMock.order.update).toHaveBeenCalledWith({
      where: { id: 2n },
      data: { status: "FILLED" },
    });
    expect(result.status).toBe("FILLED");
  });

  it("reconcileOrderExecution accepts PARTIALLY_FILLED status when trades and settlement references line up", async () => {
    prismaMock.order.findUniqueOrThrow.mockResolvedValue({
      id: 3n,
      qty: new Decimal("10"),
      status: "PARTIALLY_FILLED",
    });
    prismaMock.trade.findMany.mockResolvedValue([
      {
        id: 301n,
        qty: new Decimal("4"),
        createdAt: new Date("2026-04-17T00:00:00Z"),
      },
    ]);
    prismaMock.ledgerTransaction.findMany.mockResolvedValue([
      { referenceId: "301:FILL_SETTLEMENT" },
    ]);

    const result = await reconcileOrderExecution(3n, prismaMock as any);

    expect(result).toEqual(
      expect.objectContaining({
        orderId: "3",
        status: "PARTIALLY_FILLED",
        expectedStatus: "PARTIALLY_FILLED",
        tradeCount: 1,
        ledgerTransactionCount: 1,
        executedQty: "4",
        remainingQty: "6",
      }),
    );
  });

  it("reconcileOrderExecution rejects stale OPEN status when partial executions already exist", async () => {
    prismaMock.order.findUniqueOrThrow.mockResolvedValue({
      id: 4n,
      qty: new Decimal("10"),
      status: "OPEN",
    });
    prismaMock.trade.findMany.mockResolvedValue([
      {
        id: 401n,
        qty: new Decimal("4"),
        createdAt: new Date("2026-04-17T00:00:00Z"),
      },
    ]);
    prismaMock.ledgerTransaction.findMany.mockResolvedValue([
      { referenceId: "401:FILL_SETTLEMENT" },
    ]);

    await expect(reconcileOrderExecution(4n, prismaMock as any)).rejects.toThrow(
      /Order status mismatch/i,
    );
  });

  it("reconcileOrderExecution rejects settlement count mismatches for the same lifecycle", async () => {
    prismaMock.order.findUniqueOrThrow.mockResolvedValue({
      id: 5n,
      qty: new Decimal("10"),
      status: "PARTIALLY_FILLED",
    });
    prismaMock.trade.findMany.mockResolvedValue([
      {
        id: 501n,
        qty: new Decimal("4"),
        createdAt: new Date("2026-04-17T00:00:00Z"),
      },
      {
        id: 502n,
        qty: new Decimal("1"),
        createdAt: new Date("2026-04-17T00:01:00Z"),
      },
    ]);
    prismaMock.ledgerTransaction.findMany.mockResolvedValue([
      { referenceId: "501:FILL_SETTLEMENT" },
    ]);

    await expect(reconcileOrderExecution(5n, prismaMock as any)).rejects.toThrow(
      /Trade to ledger transaction count mismatch/i,
    );
  });
});
''')
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_text)

print("Patched package.json, updated execution.ts maker matching semantics, and wrote apps/api/test/ledger.lifecycle.test.ts for Phase 3A.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 3A patch applied."
