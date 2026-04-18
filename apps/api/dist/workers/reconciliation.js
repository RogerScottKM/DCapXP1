"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runReconciliation = runReconciliation;
exports.startReconciliationWorker = startReconciliationWorker;
exports.stopReconciliationWorker = stopReconciliationWorker;
const library_1 = require("@prisma/client/runtime/library");
const prisma_1 = require("../lib/prisma");
const security_audit_1 = require("../lib/service/security-audit");
const runtime_status_1 = require("../lib/runtime/runtime-status");
const alerting_1 = require("../lib/runtime/alerting");
async function checkGlobalBalance() {
    const results = [];
    try {
        const rows = await prisma_1.prisma.$queryRaw `
        SELECT
          "assetCode",
          SUM(CASE WHEN side = 'DEBIT' THEN amount ELSE 0 END) AS total_debit,
          SUM(CASE WHEN side = 'CREDIT' THEN amount ELSE 0 END) AS total_credit
        FROM "LedgerPosting"
        GROUP BY "assetCode"
      `;
        for (const row of rows) {
            const debit = new library_1.Decimal(row.total_debit ?? 0);
            const credit = new library_1.Decimal(row.total_credit ?? 0);
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
    }
    catch (error) {
        results.push({
            check: "GLOBAL_BALANCE",
            ok: false,
            details: { error: error?.message ?? "Query failed" },
        });
    }
    return results;
}
async function checkNonNegativeBalances() {
    const results = [];
    try {
        const rows = await prisma_1.prisma.$queryRaw `
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
    `;
        if (rows.length === 0) {
            results.push({
                check: "NON_NEGATIVE_BALANCES",
                ok: true,
                details: { message: "All account balances are non-negative." },
            });
        }
        else {
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
                        balance: new library_1.Decimal(row.net_balance ?? 0).toString(),
                    },
                });
            }
        }
    }
    catch (error) {
        results.push({
            check: "NON_NEGATIVE_BALANCES",
            ok: false,
            details: { error: error?.message ?? "Query failed" },
        });
    }
    return results;
}
async function checkRecentTradeSettlement(lookbackMinutes = 30) {
    const results = [];
    try {
        const cutoff = new Date(Date.now() - lookbackMinutes * 60 * 1000);
        const recentTrades = await prisma_1.prisma.trade.findMany({
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
        const ledgerTransactions = await prisma_1.prisma.ledgerTransaction.findMany({
            where: {
                referenceType: "ORDER_EVENT",
                referenceId: { in: expectedReferenceIds },
            },
            select: { referenceId: true },
        });
        const settledRefs = new Set(ledgerTransactions.map((lt) => lt.referenceId));
        const missing = [];
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
        }
        else {
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
    }
    catch (error) {
        results.push({
            check: "RECENT_TRADE_SETTLEMENT",
            ok: false,
            details: { error: error?.message ?? "Query failed" },
        });
    }
    return results;
}
async function checkOrderStatusConsistency() {
    const results = [];
    try {
        const activeOrders = await prisma_1.prisma.order.findMany({
            where: {
                status: { in: ["OPEN", "PARTIALLY_FILLED"] },
            },
            take: 100,
            orderBy: { createdAt: "desc" },
        });
        let mismatches = 0;
        const mismatchDetails = [];
        for (const order of activeOrders) {
            const [buyAgg, sellAgg] = await Promise.all([
                prisma_1.prisma.trade.aggregate({
                    where: { buyOrderId: order.id },
                    _sum: { qty: true },
                }),
                prisma_1.prisma.trade.aggregate({
                    where: { sellOrderId: order.id },
                    _sum: { qty: true },
                }),
            ]);
            const executedQty = new library_1.Decimal(buyAgg._sum.qty ?? 0).plus(new library_1.Decimal(sellAgg._sum.qty ?? 0));
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
    }
    catch (error) {
        results.push({
            check: "ORDER_STATUS_CONSISTENCY",
            ok: false,
            details: { error: error?.message ?? "Query failed" },
        });
    }
    return results;
}
async function runReconciliation() {
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
        console.error(`[reconciliation] ${failures.length} check(s) FAILED:`, JSON.stringify(failures, null, 2));
        await (0, security_audit_1.recordSecurityAudit)({
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
    }
    else {
        console.log(`[reconciliation] all ${allResults.length} checks passed`);
    }
    (0, runtime_status_1.noteReconciliationRun)(allResults);
    const runtimeFailures = allResults.filter((result) => !result.ok);
    if (runtimeFailures.length > 0) {
        await (0, alerting_1.dispatchRuntimeAlert)({
            type: "RECONCILIATION_FAILURE",
            summary: `[reconciliation] ${runtimeFailures.length} check(s) failed`,
            payload: {
                failureCount: runtimeFailures.length,
                checkCount: allResults.length,
                failures: runtimeFailures.slice(0, 10),
            },
        }).catch(() => undefined);
    }
    return allResults;
}
let intervalHandle = null;
const DEFAULT_INTERVAL_MS = 60 * 1000;
function startReconciliationWorker(intervalMs = DEFAULT_INTERVAL_MS) {
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
function stopReconciliationWorker() {
    if (intervalHandle) {
        clearInterval(intervalHandle);
        intervalHandle = null;
        console.log("[reconciliation] worker stopped");
    }
}
