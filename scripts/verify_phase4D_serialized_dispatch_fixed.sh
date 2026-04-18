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
DISPATCH="$ROOT/apps/api/src/lib/matching/serialized-dispatch.ts"
SUBMIT="$ROOT/apps/api/src/lib/matching/submit-limit-order.ts"
INDEX="$ROOT/apps/api/src/lib/matching/index.ts"
TEST="$ROOT/apps/api/test/matching-serialized-dispatch.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$DISPATCH" ] || fail "serialized-dispatch.ts exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$INDEX" ] || fail "matching index exists"
[ -f "$TEST" ] || fail "matching-serialized-dispatch.test.ts exists"

contains "$PKG" '"test:matching:serialized-dispatch"' "package.json includes serialized dispatch test script"
contains "$PKG" 'vitest run test/matching-serialized-dispatch.test.ts' "package.json serialized dispatch script points at focused test file"

contains "$DISPATCH" 'export async function runSerializedByKey' "dispatcher exports runSerializedByKey"
contains "$DISPATCH" 'export function buildSymbolModeKey' "dispatcher exports buildSymbolModeKey"
contains "$DISPATCH" 'export function getSerializedLaneCount' "dispatcher exports lane count helper"
contains "$DISPATCH" 'export function resetSerializedDispatchForTests' "dispatcher exports reset helper"

contains "$SUBMIT" 'import { buildSymbolModeKey, runSerializedByKey } from "./serialized-dispatch";' "submit service imports serialized dispatch helpers"
contains "$SUBMIT" 'selectedEngine.name === "IN_MEMORY_MATCHER"' "submit service only serializes in-memory engine path"
contains "$SUBMIT" 'buildSymbolModeKey(input.symbol, String(input.mode))' "submit service serializes by symbol:mode key"
contains "$SUBMIT" 'runSerializedByKey(' "submit service uses serialized dispatch"

contains "$INDEX" 'export * from "./serialized-dispatch";' "matching index re-exports serialized dispatch helper"

contains "$TEST" 'serializes tasks for the same symbol:mode key' "4D tests cover same-key serialization"
contains "$TEST" 'allows different symbol:mode keys to progress independently' "4D tests cover independent keys"
contains "$TEST" 'submitLimitOrder serializes only the in-memory engine path by symbol:mode' "4D tests cover submitLimitOrder serialization seam"
contains "$TEST" 'buildSymbolModeKey uses symbol and mode deterministically' "4D tests cover key builder"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 4D tests"
if (cd "$ROOT" && pnpm --filter api test:matching:serialized-dispatch); then
  pass "focused Phase 4D tests pass"
else
  fail "focused Phase 4D tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 4D checks passed."
