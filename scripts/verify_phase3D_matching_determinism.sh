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
HELPER="$ROOT/apps/api/src/lib/ledger/matching-priority.ts"
TEST="$ROOT/apps/api/test/ledger.matching-determinism.test.ts"
INDEX="$ROOT/apps/api/src/lib/ledger/index.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$EXEC" ] || fail "execution.ts exists"
[ -f "$HELPER" ] || fail "matching-priority helper exists"
[ -f "$TEST" ] || fail "ledger.matching-determinism.test.ts exists"

contains "$PKG" '"test:ledger:matching-determinism"' "package.json includes matching determinism test script"
contains "$PKG" 'vitest run test/ledger.matching-determinism.test.ts' "package.json matching determinism script points at focused test file"

contains "$HELPER" 'export function buildMakerOrderByForTaker' "helper exports buildMakerOrderByForTaker"
contains "$HELPER" 'export function compareMakerPriority' "helper exports compareMakerPriority"
contains "$HELPER" 'export function sortMakersForTaker' "helper exports sortMakersForTaker"

contains "$EXEC" 'import { buildMakerOrderByForTaker } from "./matching-priority";' "execution.ts imports matching-priority helper"
contains "$EXEC" 'orderBy: buildMakerOrderByForTaker(order.side),' "execution.ts uses centralized price-time orderBy"

if [ -f "$INDEX" ]; then
  contains "$INDEX" 'export * from "./matching-priority";' "ledger index re-exports matching-priority helper"
fi

contains "$TEST" 'builds ascending price then ascending time for BUY takers' "determinism tests cover BUY orderBy"
contains "$TEST" 'builds descending price then ascending time for SELL takers' "determinism tests cover SELL orderBy"
contains "$TEST" 'uses earlier createdAt as the tie-breaker at equal price' "determinism tests cover time tie-break"
contains "$TEST" 'sorts BUY-side maker candidates deterministically across price levels and ties' "determinism tests cover BUY sorting"
contains "$TEST" 'sorts SELL-side maker candidates deterministically across price levels and ties' "determinism tests cover SELL sorting"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused matching determinism tests"
if (cd "$ROOT" && pnpm --filter api test:ledger:matching-determinism); then
  pass "focused matching determinism tests pass"
else
  fail "focused matching determinism tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 3D checks passed."
