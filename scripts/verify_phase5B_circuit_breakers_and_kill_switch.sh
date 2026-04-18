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
HELPER="$ROOT/apps/api/src/lib/matching/admission-controls.ts"
SUBMIT="$ROOT/apps/api/src/lib/matching/submit-limit-order.ts"
INDEX="$ROOT/apps/api/src/lib/matching/index.ts"
TEST="$ROOT/apps/api/test/admission-controls.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$HELPER" ] || fail "admission-controls.ts exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$INDEX" ] || fail "matching index exists"
[ -f "$TEST" ] || fail "admission-controls.test.ts exists"

contains "$PKG" '"test:matching:admission-controls"' "package.json includes admission-controls test script"
contains "$PKG" 'vitest run test/admission-controls.test.ts' "package.json admission-controls script points at focused test file"

contains "$HELPER" 'export class AdmissionControlError extends Error' "admission-controls exports AdmissionControlError"
contains "$HELPER" 'export function computePriceDeviationBps' "admission-controls exports price deviation calculator"
contains "$HELPER" 'export function assertWithinPriceBand' "admission-controls exports price-band guard"
contains "$HELPER" 'export function assertSymbolEnabled' "admission-controls exports symbol kill-switch guard"
contains "$HELPER" 'export function consumeSlidingWindowLimit' "admission-controls exports sliding-window limiter"
contains "$HELPER" 'export async function enforceAdmissionControls' "admission-controls exports main enforcement hook"
contains "$HELPER" 'MATCH_DISABLED_SYMBOLS' "admission-controls supports env disabled symbol list"
contains "$HELPER" 'MATCH_MAX_PRICE_DEVIATION_BPS' "admission-controls supports env price deviation band"
contains "$HELPER" 'MATCH_MAX_ORDERS_PER_MINUTE_PER_USER' "admission-controls supports per-user rate limits"
contains "$HELPER" 'MATCH_MAX_ORDERS_PER_MINUTE_PER_SYMBOL' "admission-controls supports per-symbol aggregate rate limits"

contains "$SUBMIT" 'import { enforceAdmissionControls } from "./admission-controls";' "submit service imports admission controls"
contains "$SUBMIT" 'await enforceAdmissionControls({' "submit service enforces circuit breakers before order create"
contains "$SUBMIT" 'symbol: input.symbol,' "submit service passes symbol into admission controls"
contains "$SUBMIT" 'mode: String(input.mode),' "submit service passes mode into admission controls"

contains "$INDEX" 'export * from "./admission-controls";' "matching index re-exports admission controls"

contains "$TEST" 'rejects disabled symbols from either market.enabled or env kill switch' "5B tests cover kill switch"
contains "$TEST" 'rejects prices outside the configured max deviation band' "5B tests cover price band"
contains "$TEST" 'enforces per-user and per-symbol sliding-window rate limits' "5B tests cover rate limits"
contains "$TEST" 'enforceAdmissionControls consults latest trade, kill switch, and both rate windows' "5B tests cover integrated enforcement"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 5B tests"
if (cd "$ROOT" && pnpm --filter api test:matching:admission-controls); then
  pass "focused Phase 5B tests pass"
else
  fail "focused Phase 5B tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 5B checks passed."
