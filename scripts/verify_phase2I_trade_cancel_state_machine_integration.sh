#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }
contains() {
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
TEST="$ROOT/apps/api/test/trade.cancel.guard.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$TRADE" ] || fail "trade.ts exists"
[ -f "$TEST" ] || fail "trade.cancel.guard.test.ts exists"

contains "$PKG" '"test:routes:trade-cancel"' "package.json includes trade-cancel test script"
contains "$PKG" 'vitest run test/trade.cancel.guard.test.ts' "package.json trade-cancel script points at focused test file"

contains "$TRADE" 'canCancel' "trade route imports or uses canCancel"
contains "$TRADE" 'ORDER_STATUS' "trade route imports or uses ORDER_STATUS"
contains "$TRADE" 'if (!canCancel(order.status)) {' "trade route uses canCancel for cancel validation"
contains "$TRADE" 'Cannot cancel order in status ${order.status}.' "trade route returns status-specific cancel error"
contains "$TRADE" 'Order has no remaining quantity to cancel.' "trade route guards zero remaining quantity"
contains "$TRADE" 'status: ORDER_STATUS.CANCELLED' "trade route uses ORDER_STATUS.CANCELLED"

contains "$TEST" 'allows cancelling a PARTIALLY_FILLED order with remaining quantity' "trade-cancel tests cover PARTIALLY_FILLED success"
contains "$TEST" 'rejects cancelling a FILLED order' "trade-cancel tests cover FILLED rejection"
contains "$TEST" 'rejects cancelling a CANCEL_PENDING order' "trade-cancel tests cover CANCEL_PENDING rejection"
contains "$TEST" 'rejects cancelling an order with no remaining quantity' "trade-cancel tests cover zero-remaining rejection"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused trade-cancel tests"
if (cd "$ROOT" && pnpm --filter api test:routes:trade-cancel); then
  pass "focused trade-cancel tests pass"
else
  fail "focused trade-cancel tests pass"
fi

echo

echo "Resolved repo root: $ROOT"
echo "All Phase 2I checks passed."
