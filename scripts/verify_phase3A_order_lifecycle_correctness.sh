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
TEST="$ROOT/apps/api/test/ledger.lifecycle.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$EXEC" ] || fail "execution.ts exists"
[ -f "$TEST" ] || fail "ledger.lifecycle.test.ts exists"

contains "$PKG" '"test:ledger:lifecycle"' "package.json includes lifecycle test script"
contains "$PKG" 'vitest run test/ledger.lifecycle.test.ts' "package.json lifecycle script points at focused test file"

contains "$EXEC" 'status: { in: ["OPEN", "PARTIALLY_FILLED"] }' "execution path matches against OPEN and PARTIALLY_FILLED maker orders"
contains "$EXEC" 'syncOrderStatusFromTrades' "execution.ts exports syncOrderStatusFromTrades"
contains "$EXEC" 'reconcileOrderExecution' "execution.ts exports reconcileOrderExecution"
contains "$EXEC" 'deriveOrderStatus' "execution.ts derives status from execution totals"

contains "$TEST" 'syncOrderStatusFromTrades updates OPEN to PARTIALLY_FILLED after a partial execution' "lifecycle tests cover partial-fill status sync"
contains "$TEST" 'syncOrderStatusFromTrades updates to FILLED when cumulative execution reaches order quantity' "lifecycle tests cover full-fill status sync"
contains "$TEST" 'reconcileOrderExecution accepts PARTIALLY_FILLED status when trades and settlement references line up' "lifecycle tests cover healthy partially-filled reconciliation"
contains "$TEST" 'reconcileOrderExecution rejects stale OPEN status when partial executions already exist' "lifecycle tests cover stale OPEN rejection"
contains "$TEST" 'reconcileOrderExecution rejects settlement count mismatches for the same lifecycle' "lifecycle tests cover settlement count mismatch"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused lifecycle tests"
if (cd "$ROOT" && pnpm --filter api test:ledger:lifecycle); then
  pass "focused lifecycle tests pass"
else
  fail "focused lifecycle tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 3A checks passed."
