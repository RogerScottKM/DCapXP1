#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-.}"

pass(){ echo "[PASS] $1"; }
fail(){ echo "[FAIL] $1"; exit 1; }
check_contains(){ local f="$1"; local p="$2"; local l="$3"; if grep -Fq "$p" "$f"; then pass "$l"; else fail "$l"; fi }

PKG="$ROOT/apps/api/package.json"
EXEC="$ROOT/apps/api/src/lib/ledger/execution.ts"
INDEX="$ROOT/apps/api/src/lib/ledger/index.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"
TEST="$ROOT/apps/api/test/ledger.execution.test.ts"

check_contains "$PKG" 'test:ledger:execution' 'package.json includes ledger execution test script'
check_contains "$EXEC" 'export async function executeLimitOrderAgainstBook' 'execution helper exports executeLimitOrderAgainstBook'
check_contains "$EXEC" 'export async function reconcileOrderExecution' 'execution helper exports reconcileOrderExecution'
check_contains "$EXEC" 'export function computeQuoteFeeAmount' 'execution helper exports quote fee calculator'
check_contains "$EXEC" 'export function computeBuyPriceImprovementReleaseAmount' 'execution helper exports price improvement calculator'
check_contains "$EXEC" 'quoteFeeBps' 'execution helper supports fee booking inputs'
check_contains "$EXEC" 'ORDER_BUY_PRICE_IMPROVEMENT_RELEASE' 'execution helper books buy-side price improvement release'
check_contains "$EXEC" 'settleMatchedTrade' 'execution helper settles matched trades into ledger'
check_contains "$EXEC" 'reconcileTradeSettlement' 'execution helper runs trade settlement reconciliation'
check_contains "$EXEC" 'ledgerTransactions.length !== trades.length' 'execution helper reconciles order trades to ledger transactions'
check_contains "$INDEX" 'export * from "./execution";' 'ledger index re-exports execution helper'
check_contains "$TRADE" 'executeLimitOrderAgainstBook' 'trade route uses actual execution path settlement on order placement'
check_contains "$TRADE" 'reconcileOrderExecution' 'trade route reconciles orders after execution'
check_contains "$TRADE" 'quoteFeeBps' 'trade route accepts fee booking input on placement'
check_contains "$TRADE" 'getOrderRemainingQty' 'trade route uses remaining quantity for cancellation'
check_contains "$TRADE" 'Phase 2D only wires LIMIT order execution and ledger booking.' 'trade route documents narrowed execution scope'
check_contains "$TEST" 'detects crossing prices' 'execution test covers crossing logic'
check_contains "$TEST" 'computes quote fees from bps' 'execution test covers fee calculation'
check_contains "$TEST" 'price improvement release amount' 'execution test covers price improvement release'

echo
echo "All Phase 2D static checks passed."
