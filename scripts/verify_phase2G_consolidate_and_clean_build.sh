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
EXEC="$ROOT/apps/api/src/lib/ledger/execution.ts"
RECON="$ROOT/apps/api/src/lib/ledger/reconciliation.ts"
ORDER_STATE="$ROOT/apps/api/src/lib/ledger/order-state.ts"
HOLD="$ROOT/apps/api/src/lib/ledger/hold-release.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"
SMOKE="$ROOT/apps/api/test/ledger.phase2.smoke.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$EXEC" ] || fail "execution.ts exists"
[ -f "$RECON" ] || fail "reconciliation.ts exists"
[ -f "$ORDER_STATE" ] || fail "order-state.ts exists"
[ -f "$HOLD" ] || fail "hold-release.ts exists"
[ -f "$TRADE" ] || fail "trade.ts exists"
[ -f "$SMOKE" ] || fail "ledger.phase2.smoke.test.ts exists"

contains "$PKG" '"test:ledger:phase2-smoke"' "package.json includes phase2 smoke test script"
contains "$PKG" '"test:ledger:phase2"' "package.json includes combined phase2 test script"
contains "$PKG" 'vitest run test/ledger.phase2.smoke.test.ts' "phase2 smoke script points at focused smoke test"
contains "$PKG" 'test/ledger.reconciliation.test.ts test/ledger.execution.test.ts test/ledger.order-state.test.ts test/ledger.hold-release.test.ts test/ledger.phase2.smoke.test.ts' "combined phase2 script runs the full ledger chain"

contains "$EXEC" 'executeLimitOrderAgainstBook' "execution helper exports executeLimitOrderAgainstBook"
contains "$EXEC" 'reconcileOrderExecution' "execution helper exports reconcileOrderExecution"
contains "$EXEC" 'syncOrderStatusFromTrades' "execution helper exports syncOrderStatusFromTrades"
contains "$EXEC" 'releaseResidualHoldAfterExecution' "execution helper exports residual hold release"
contains "$EXEC" 'reconcileCumulativeFills' "execution helper exports cumulative fill reconciliation"

contains "$RECON" 'assertTradeSettlementConsistency' "reconciliation helper exports settlement consistency assertion"
contains "$RECON" 'reconcileTradeSettlement' "reconciliation helper exports reconciliation loader"

contains "$ORDER_STATE" 'computeRemainingQty' "order-state helper exports remaining quantity calculator"
contains "$ORDER_STATE" 'deriveOrderStatus' "order-state helper exports current persisted status derivation"
contains "$ORDER_STATE" 'assertExecutedQtyWithinOrder' "order-state helper exports overfill guard"

contains "$HOLD" 'computeReservedQuote' "hold-release helper exports reserved quote calculator"
contains "$HOLD" 'computeExecutedQuote' "hold-release helper exports executed quote calculator"
contains "$HOLD" 'computeBuyHeldQuoteRelease' "hold-release helper exports residual held quote release"
contains "$HOLD" 'assertCumulativeFillWithinOrder' "hold-release helper exports cumulative overfill guard"

contains "$TRADE" 'reserveOrderOnPlacement' "trade route reserves funds on order placement"
contains "$TRADE" 'executeLimitOrderAgainstBook' "trade route executes against the resting book"
contains "$TRADE" 'reconcileOrderExecution' "trade route reconciles orders after placement"
contains "$TRADE" 'releaseOrderOnCancel' "trade route releases held funds on cancel"
contains "$TRADE" 'syncOrderStatusFromTrades' "trade route syncs status from actual fills"
contains "$TRADE" 'reconcileTradeSettlement' "trade route reconciles fill settlement"

contains "$SMOKE" 'models reserve to partial fill under current persisted status semantics' "smoke test covers reserve to partial fill"
contains "$SMOKE" 'models final buy completion with residual hold release and price improvement release' "smoke test covers final fill release math"
contains "$SMOKE" 'accepts a synthetic fill settlement reconciliation record' "smoke test covers settlement consistency"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running combined phase2 ledger tests"
if (cd "$ROOT" && pnpm --filter api test:ledger:phase2); then
  pass "combined phase2 ledger tests pass"
else
  fail "combined phase2 ledger tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 2G checks passed."
