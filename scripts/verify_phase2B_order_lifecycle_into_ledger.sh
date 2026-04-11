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
TRADE="$ROOT/apps/api/src/routes/trade.ts"
LIFECYCLE="$ROOT/apps/api/src/lib/ledger/order-lifecycle.ts"
INDEX="$ROOT/apps/api/src/lib/ledger/index.ts"
TESTFILE="$ROOT/apps/api/test/ledger.order-lifecycle.test.ts"

check_contains "$PKG" 'test:ledger:lifecycle' "package.json includes ledger lifecycle test script"
check_contains "$LIFECYCLE" 'reserveOrderOnPlacement' "order lifecycle helper exports reserveOrderOnPlacement"
check_contains "$LIFECYCLE" 'releaseOrderOnCancel' "order lifecycle helper exports releaseOrderOnCancel"
check_contains "$LIFECYCLE" 'settleMatchedTrade' "order lifecycle helper exports settleMatchedTrade"
check_contains "$LIFECYCLE" 'ORDER_PLACE_HOLD' "order lifecycle helper records order placement hold events"
check_contains "$LIFECYCLE" 'ORDER_CANCEL_RELEASE' "order lifecycle helper records cancel release events"
check_contains "$LIFECYCLE" 'ORDER_FILL_SETTLEMENT' "order lifecycle helper records fill settlement events"
check_contains "$LIFECYCLE" 'ensureUserLedgerAccounts' "order lifecycle helper uses user ledger accounts"
check_contains "$LIFECYCLE" 'ensureSystemLedgerAccounts' "order lifecycle helper uses system ledger accounts"
check_contains "$LIFECYCLE" 'assertAccountHasBalance' "order lifecycle helper guards against insufficient balances"
check_contains "$LIFECYCLE" 'findExistingReference' "order lifecycle helper uses reference idempotency lookup"
check_contains "$INDEX" './order-lifecycle' "ledger index re-exports order lifecycle helper"
check_contains "$TRADE" 'reserveOrderOnPlacement' "trade route reserves ledger balances on order placement"
check_contains "$TRADE" '/orders/:orderId/cancel' "trade route exposes order cancellation route"
check_contains "$TRADE" 'releaseOrderOnCancel' "trade route releases ledger balances on cancel"
check_contains "$TRADE" 'Phase 2B only wires LIMIT order ledger booking.' "trade route clearly limits scope to LIMIT orders"
check_contains "$TRADE" 'prisma.order.create' "trade route persists orders before ledger booking"
check_contains "$TESTFILE" 'reserveOrderOnPlacement' "ledger lifecycle test covers placement hold"
check_contains "$TESTFILE" 'releaseOrderOnCancel' "ledger lifecycle test covers cancellation release"
check_contains "$TESTFILE" 'settleMatchedTrade' "ledger lifecycle test covers fill settlement"

echo

echo "All Phase 2B static checks passed."
