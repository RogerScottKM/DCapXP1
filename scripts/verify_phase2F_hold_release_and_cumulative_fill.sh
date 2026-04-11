#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-.}"

pass(){ echo "[PASS] $1"; }
fail(){ echo "[FAIL] $1"; exit 1; }
contains(){ grep -Fq "$2" "$1"; }

PKG="$ROOT/apps/api/package.json"
HOLD="$ROOT/apps/api/src/lib/ledger/hold-release.ts"
IDX="$ROOT/apps/api/src/lib/ledger/index.ts"
EXEC="$ROOT/apps/api/src/lib/ledger/execution.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"
TEST="$ROOT/apps/api/test/ledger.hold-release.test.ts"

contains "$PKG" '"test:ledger:hold-release"' && pass "package.json includes ledger hold-release test script" || fail "package.json includes ledger hold-release test script"

contains "$HOLD" 'computeBuyHeldQuoteRelease' && pass "hold-release helper exports buy held release calculator" || fail "hold-release helper exports buy held release calculator"
contains "$HOLD" 'assertCumulativeFillWithinOrder' && pass "hold-release helper exports cumulative fill guard" || fail "hold-release helper exports cumulative fill guard"
contains "$HOLD" 'computeExecutedQuote' && pass "hold-release helper exports executed quote calculator" || fail "hold-release helper exports executed quote calculator"
contains "$HOLD" 'computeRemainingQtyFromCumulative' && pass "hold-release helper exports remaining qty calculator" || fail "hold-release helper exports remaining qty calculator"

contains "$IDX" 'from "./hold-release"' && pass "ledger index re-exports hold-release helper" || fail "ledger index re-exports hold-release helper"

contains "$EXEC" 'releaseResidualHoldAfterExecution' && pass "execution helper exports residual hold release" || fail "execution helper exports residual hold release"
contains "$EXEC" 'reconcileCumulativeFills' && pass "execution helper exports cumulative fill reconciliation" || fail "execution helper exports cumulative fill reconciliation"
contains "$EXEC" 'FINAL_RESIDUAL_RELEASE' && pass "execution helper books final residual release reference" || fail "execution helper books final residual release reference"
contains "$EXEC" 'assertCumulativeFillWithinOrder' && pass "execution helper guards cumulative fills" || fail "execution helper guards cumulative fills"

contains "$TRADE" 'buyHeldRelease' && pass "trade route releases unused held quote on final buy completion" || fail "trade route releases unused held quote on final buy completion"
contains "$TRADE" 'buyFillCheck' && pass "trade route computes cumulative fill check for buy order" || fail "trade route computes cumulative fill check for buy order"
contains "$TRADE" 'sellFillCheck' && pass "trade route computes cumulative fill check for sell order" || fail "trade route computes cumulative fill check for sell order"
contains "$TRADE" 'cumulativeFillCheck' && pass "trade route includes cumulative fill reconciliation on placement path" || fail "trade route includes cumulative fill reconciliation on placement path"

contains "$TEST" 'computes residual buy hold release on final completion' && pass "hold-release test covers final residual release" || fail "hold-release test covers final residual release"
contains "$TEST" 'guards cumulative fills from exceeding order quantity' && pass "hold-release test covers cumulative overfill guard" || fail "hold-release test covers cumulative overfill guard"

echo
echo "All Phase 2F static checks passed."
