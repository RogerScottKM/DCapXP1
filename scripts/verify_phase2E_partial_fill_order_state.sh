#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }
check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

PKG="$ROOT/apps/api/package.json"
ORDER_STATE="$ROOT/apps/api/src/lib/ledger/order-state.ts"
EXEC="$ROOT/apps/api/src/lib/ledger/execution.ts"
INDEX="$ROOT/apps/api/src/lib/ledger/index.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"
TEST="$ROOT/apps/api/test/ledger.order-state.test.ts"

check_contains "$PKG" 'test:ledger:order-state' "package.json includes ledger order-state test script"
check_contains "$ORDER_STATE" 'computeRemainingQty' "order-state helper exports remaining quantity calculator"
check_contains "$ORDER_STATE" 'deriveOrderStatus' "order-state helper exports order status derivation"
check_contains "$ORDER_STATE" 'assertExecutedQtyWithinOrder' "order-state helper exports overfill guard"
check_contains "$ORDER_STATE" 'CANCELLED' "order-state helper preserves cancelled orders"
check_contains "$EXEC" 'syncOrderStatusFromTrades' "execution helper exports order-status sync"
check_contains "$EXEC" 'assertExecutedQtyWithinOrder' "execution helper guards against overfills"
check_contains "$EXEC" 'deriveOrderStatus' "execution helper derives expected status"
check_contains "$EXEC" 'Order status mismatch' "execution helper reconciles order status correctness"
check_contains "$INDEX" 'export * from "./order-state";' "ledger index re-exports order-state helper"
check_contains "$TRADE" 'syncOrderStatusFromTrades' "trade route syncs status from actual trade fills"
check_contains "$TRADE" 'buyOrderReconciliation' "trade route reconciles buy order after demo fill"
check_contains "$TRADE" 'sellOrderReconciliation' "trade route reconciles sell order after demo fill"
check_contains "$TEST" 'computes remaining quantity for partial fills' "order-state test covers partial remaining quantity"
check_contains "$TEST" 'derives OPEN for partially filled open orders and FILLED for complete fills' "order-state test covers OPEN/FILLED derivation"
check_contains "$TEST" 'preserves CANCELLED and rejects overfills' "order-state test covers cancelled/overfill behavior"

echo
echo "All Phase 2E static checks passed."
