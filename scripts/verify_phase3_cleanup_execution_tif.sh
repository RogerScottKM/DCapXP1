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
TEST="$ROOT/apps/api/test/ledger.execution.phase3-cleanup.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$EXEC" ] || fail "execution.ts exists"
[ -f "$TEST" ] || fail "ledger.execution.phase3-cleanup.test.ts exists"

contains "$PKG" '"test:ledger:execution-cleanup"' "package.json includes execution-cleanup test script"
contains "$PKG" 'vitest run test/ledger.execution.phase3-cleanup.test.ts' "package.json execution-cleanup script points at focused test file"

contains "$EXEC" 'import { releaseOrderOnCancel, settleMatchedTrade } from "./order-lifecycle";' "execution.ts uses static releaseOrderOnCancel import"
contains "$EXEC" 'if (!canReceiveFills(takerOrder.status)) {' "execution.ts uses canReceiveFills for taker guard"
contains "$EXEC" 'assertValidTransition(order.status, nextStatus);' "execution.ts validates status transitions before persistence"
contains "$EXEC" 'const freshMaker = await db.order.findUnique({ where: { id: makerOrder.id } });' "execution.ts refreshes maker state before fill"
contains "$EXEC" 'if (!freshMaker || !canReceiveFills(freshMaker.status)) {' "execution.ts skips non-receivable makers"
contains "$EXEC" 'assertPostOnlyWouldRest(' "execution.ts enforces POST_ONLY before matching"
contains "$EXEC" 'assertFokCanFullyFill(takerOrder.qty, fillableLiquidity);' "execution.ts enforces FOK precheck"
contains "$EXEC" 'const tifAction = deriveTifRestingAction(tif, executed, takerOrder.qty);' "execution.ts derives post-match TIF action"
contains "$EXEC" 'await releaseOrderOnCancel(' "execution.ts releases IOC/FOK remainder through releaseOrderOnCancel"
contains "$EXEC" 'assertValidTransition(ORDER_STATUS.OPEN, ORDER_STATUS.CANCELLED);' "execution.ts validates final cancel transition for TIF remainder"

contains "$TEST" 'allows a PARTIALLY_FILLED taker to re-enter matching' "cleanup tests cover PARTIALLY_FILLED taker"
contains "$TEST" 'skips a maker that turned CANCELLED after initial candidate selection' "cleanup tests cover fresh-maker recheck"
contains "$TEST" 'cancels IOC remainder through releaseOrderOnCancel and marks the order CANCELLED' "cleanup tests cover IOC remainder cancel"
contains "$TEST" 'syncOrderStatusFromTrades preserves FILLED as a terminal state' "cleanup tests cover terminal status preservation"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused execution cleanup tests"
if (cd "$ROOT" && pnpm --filter api test:ledger:execution-cleanup); then
  pass "focused execution cleanup tests pass"
else
  fail "focused execution cleanup tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 3 cleanup checks passed."
