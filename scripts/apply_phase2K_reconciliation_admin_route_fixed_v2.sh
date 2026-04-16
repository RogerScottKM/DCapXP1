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
import sys
from textwrap import dedent

root = Path(sys.argv[1])

route_path = root / "apps/api/src/routes/reconciliation.ts"
worker_path = root / "apps/api/src/workers/reconciliation.ts"

if not route_path.exists():
    raise SystemExit(f"Missing reconciliation route: {route_path}")

worker_ts = dedent("""import { Decimal } from "@prisma/client/runtime/library";

import { prisma } from "../lib/prisma";
import { recordSecurityAudit } from "../lib/service/security-audit";

export type ReconciliationResult = {
  check: string;
  ok: boolean;
  details?: Record<string, unknown>;
};

async function checkGlobalBalance(): Promise<ReconciliationResult[]> {
  const results: ReconciliationResult[] = [];

  try {
    const rows: Array<{ assetCode: string; total_debit: Decimal | null; total_credit: Decimal | null }> =
      await prisma.$queryRaw\`
        SELECT
          "assetCode",
          SUM(CASE WHEN side = 'DEBIT' THEN amount ELSE 0 END) AS total_debit,
          SUM(CASE WHEN side = 'CREDIT' THEN amount ELSE 0 END) AS total_credit
        FROM "LedgerPosting"
        GROUP BY "assetCode"
      \`;

    for (const row of rows) {
      const debit = new Decimal(row.total_debit ?? 0);
      const credit = new Decimal(row.total_credit ?? 0);
      const diff = debit.minus(credit);
      const ok = diff.eq(0);

      results.push({
        check: `GLOBAL_BALANCE:${row.assetCode}`,
        ok,
        details: {
          assetCode: row.assetCode,
          totalDebit: debit.toString(),
          totalCredit: credit.toString(),
          difference: diff.toString(),
        },
      });
    }

    if (rows.length === 0) {
      results.push({
        check: "GLOBAL_BALANCE",
        ok: true,
        details: { message: "No ledger postings found (empty ledger)." },
      });
    }
  } catch (error: any) {
    results.push({
      check: "GLOBAL_BALANCE",
      ok: false,
      details: { error: error?.message ?? "Query failed" },
    });
  }

  return results;
}

async function checkNonNegativeBalances(): Promise<ReconciliationResult[]> {
  const results: ReconciliationResult[] = [];

  try {
    const rows: Array<{
      accountId: string;
      ownerType: string;
      ownerRef: string;
      assetCode: string;
      accountType: string;
      net_balance: Decimal | null;
    }> = await prisma.$queryRaw\`
      SELECT
        a.id AS "accountId",
        a."ownerType",
        a."ownerRef",
        a."assetCode",
        a."accountType",
        COALESCE(
          SUM(CASE WHEN p.side = 'CREDIT' THEN p.amount ELSE 0 END) -
          SUM(CASE WHEN p.side = 'DEBIT' THEN p.amount ELSE 0 END),
          0
        ) AS net_balance
      FROM "LedgerAccount" a
      LEFT JOIN "LedgerPosting" p ON p."accountId" = a.id
      GROUP BY a.id, a."ownerType", a."ownerRef", a."assetCode", a."accountType"
      HAVING COALESCE(
        SUM(CASE WHEN p.side = 'CREDIT' THEN p.amount ELSE 0 END) -
        SUM(CASE WHEN p.side = 'DEBIT' THEN p.amount ELSE 0 END),
        0
      ) < 0
    \`;

    if (rows.length === 0) {
      results.push({
        check: "NON_NEGATIVE_BALANCES",
        ok: true,
        details: { message: "All account balances are non-negative." },
      });
    } else {
      for (const row of rows) {
        results.push({
          check: `NEGATIVE_BALANCE:${row.accountId}`,
          ok: false,
          details: {
            accountId: row.accountId,
            ownerType: row.ownerType,
            ownerRef: row.ownerRef,
            assetCode: row.assetCode,
            accountType: row.accountType,
            balance: new Decimal(row.net_balance ?? 0).toString(),
          },
        });
      }
    }
  } catch (error: any) {
    results.push({
      check: "NON_NEGATIVE_BALANCES",
      ok: false,
      details: { error: error?.message ?? "Query failed" },
    });
  }

  return results;
}

async function checkRecentTradeSettlement(lookbackMinutes = 30): Promise<ReconciliationResult[]> {
  const results: ReconciliationResult[] = [];

  try {
    const cutoff = new Date(Date.now() - lookbackMinutes * 60 * 1000);

    const recentTrades = await prisma.trade.findMany({
      where: { createdAt: { gte: cutoff } },
      orderBy: { createdAt: "desc" },
      take: 200,
    });

    if (recentTrades.length === 0) {
      results.push({
        check: "RECENT_TRADE_SETTLEMENT",
        ok: true,
        details: { message: "No recent trades to reconcile.", lookbackMinutes },
      });
      return results;
    }

    const expectedReferenceIds = recentTrades.map((t) => `${t.id.toString()}:FILL_SETTLEMENT`);

    const ledgerTransactions = await prisma.ledgerTransaction.findMany({
      where: {
        referenceType: "ORDER_EVENT",
        referenceId: { in: expectedReferenceIds },
      },
      select: { referenceId: true },
    });

    const settledRefs = new Set(ledgerTransactions.map((lt) => lt.referenceId));
    const missing: string[] = [];

    for (const refId of expectedReferenceIds) {
      if (!settledRefs.has(refId)) {
        missing.push(refId);
      }
    }

    if (missing.length === 0) {
      results.push({
        check: "RECENT_TRADE_SETTLEMENT",
        ok: true,
        details: {
          tradesChecked: recentTrades.length,
          allSettled: true,
          lookbackMinutes,
        },
      });
    } else {
      results.push({
        check: "RECENT_TRADE_SETTLEMENT",
        ok: false,
        details: {
          tradesChecked: recentTrades.length,
          missingSettlements: missing.length,
          missingReferenceIds: missing.slice(0, 20),
          lookbackMinutes,
        },
      });
    }
  } catch (error: any) {
    results.push({
      check: "RECENT_TRADE_SETTLEMENT",
      ok: false,
      details: { error: error?.message ?? "Query failed" },
    });
  }

  return results;
}

async function checkOrderStatusConsistency(): Promise<ReconciliationResult[]> {
  const results: ReconciliationResult[] = [];

  try {
    const activeOrders = await prisma.order.findMany({
      where: {
        status: { in: ["OPEN", "PARTIALLY_FILLED"] },
      },
      take: 100,
      orderBy: { createdAt: "desc" },
    });

    let mismatches = 0;
    const mismatchDetails: Array<Record<string, unknown>> = [];

    for (const order of activeOrders) {
      const [buyAgg, sellAgg] = await Promise.all([
        prisma.trade.aggregate({
          where: { buyOrderId: order.id },
          _sum: { qty: true },
        }),
        prisma.trade.aggregate({
          where: { sellOrderId: order.id },
          _sum: { qty: true },
        }),
      ]);

      const executedQty = new Decimal(buyAgg._sum.qty ?? 0).plus(
        new Decimal(sellAgg._sum.qty ?? 0),
      );

      const shouldBeFilled = executedQty.greaterThanOrEqualTo(order.qty);

      if (shouldBeFilled && order.status !== "FILLED") {
        mismatches++;
        mismatchDetails.push({
          orderId: order.id.toString(),
          currentStatus: order.status,
          expectedStatus: "FILLED",
          orderQty: order.qty.toString(),
          executedQty: executedQty.toString(),
        });
      }
    }

    results.push({
      check: "ORDER_STATUS_CONSISTENCY",
      ok: mismatches === 0,
      details: {
        ordersChecked: activeOrders.length,
        mismatches,
        ...(mismatchDetails.length > 0 ? { mismatchDetails: mismatchDetails.slice(0, 10) } : {}),
      },
    });
  } catch (error: any) {
    results.push({
      check: "ORDER_STATUS_CONSISTENCY",
      ok: false,
      details: { error: error?.message ?? "Query failed" },
    });
  }

  return results;
}

export async function runReconciliation(): Promise<ReconciliationResult[]> {
  const [globalBalance, negativeBalances, tradeSettlement, orderStatus] = await Promise.all([
    checkGlobalBalance(),
    checkNonNegativeBalances(),
    checkRecentTradeSettlement(),
    checkOrderStatusConsistency(),
  ]);

  const allResults = [
    ...globalBalance,
    ...negativeBalances,
    ...tradeSettlement,
    ...orderStatus,
  ];

  const failures = allResults.filter((r) => !r.ok);

  if (failures.length > 0) {
    console.error(
      `[reconciliation] ${failures.length} check(s) FAILED:`,
      JSON.stringify(failures, null, 2),
    );

    await recordSecurityAudit({
      actorType: "SYSTEM",
      actorId: null,
      action: "RECONCILIATION_FAILURE",
      resourceType: "LEDGER",
      resourceId: null,
      metadata: {
        failureCount: failures.length,
        failures: failures.slice(0, 10),
        timestamp: new Date().toISOString(),
      },
    });
  } else {
    console.log(`[reconciliation] all ${allResults.length} checks passed`);
  }

  return allResults;
}

let intervalHandle: ReturnType<typeof setInterval> | null = null;
const DEFAULT_INTERVAL_MS = 60 * 1000;

export function startReconciliationWorker(intervalMs = DEFAULT_INTERVAL_MS): void {
  if (intervalHandle) {
    console.warn("[reconciliation] worker already running");
    return;
  }

  console.log(`[reconciliation] starting worker (interval: ${intervalMs}ms)`);

  void runReconciliation().catch((error) => {
    console.error("[reconciliation] initial run failed", error);
  });

  intervalHandle = setInterval(() => {
    void runReconciliation().catch((error) => {
      console.error("[reconciliation] scheduled run failed", error);
    });
  }, intervalMs);
}

export function stopReconciliationWorker(): void {
  if (intervalHandle) {
    clearInterval(intervalHandle);
    intervalHandle = null;
    console.log("[reconciliation] worker stopped");
  }
}
""")
worker_path.parent.mkdir(parents=True, exist_ok=True)
worker_path.write_text(worker_ts)

route_text = route_path.read_text()
route_text = route_text.replace(
    'const failures = results.filter((r) => !r.ok);',
    'const failures = results.filter((r: { ok: boolean }) => !r.ok);'
)
route_path.write_text(route_text)

print("Wrote apps/api/src/workers/reconciliation.ts and patched reconciliation.ts typing for Phase 2K.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 2K patch applied."
