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
TEST="$ROOT/apps/api/test/matching.property-invariants.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$TEST" ] || fail "matching.property-invariants.test.ts exists"

contains "$PKG" '"test:matching:property-invariants"' "package.json includes property invariants test script"
contains "$PKG" 'vitest run test/matching.property-invariants.test.ts' "package.json property invariants script points at focused test file"

contains "$TEST" 'function mulberry32(seed: number)' "property test defines seeded PRNG"
contains "$TEST" 'function manualSpec' "property test defines independent matching spec"
contains "$TEST" 'matches BUY takers against best-priced asks first across randomized books' "5D tests cover BUY-side randomized priority"
contains "$TEST" 'matches SELL takers against best-priced bids first across randomized books' "5D tests cover SELL-side randomized priority"
contains "$TEST" 'preserves TIF invariants across randomized scenarios' "5D tests cover randomized TIF invariants"
contains "$TEST" 'never overfills seeded maker orders across randomized taker streams' "5D tests cover no-overfill stream invariant"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 5D tests"
if (cd "$ROOT" && pnpm --filter api test:matching:property-invariants); then
  pass "focused Phase 5D tests pass"
else
  fail "focused Phase 5D tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 5D checks passed."
