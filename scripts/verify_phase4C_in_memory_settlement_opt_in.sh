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
BOOK="$ROOT/apps/api/src/lib/matching/in-memory-order-book.ts"
ENGINE="$ROOT/apps/api/src/lib/matching/in-memory-matching-engine.ts"
SUBMIT="$ROOT/apps/api/src/lib/matching/submit-limit-order.ts"
ORDERS="$ROOT/apps/api/src/routes/orders.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"
INDEX="$ROOT/apps/api/src/lib/matching/index.ts"
TEST="$ROOT/apps/api/test/in-memory-settlement-integration.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$BOOK" ] || fail "in-memory-order-book.ts exists"
[ -f "$ENGINE" ] || fail "in-memory-matching-engine.ts exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$ORDERS" ] || fail "orders.ts exists"
[ -f "$TRADE" ] || fail "trade.ts exists"
[ -f "$INDEX" ] || fail "matching index exists"
[ -f "$TEST" ] || fail "in-memory-settlement-integration.test.ts exists"

contains "$PKG" '"test:matching:in-memory-settlement"' "package.json includes in-memory settlement test script"
contains "$PKG" 'vitest run test/in-memory-settlement-integration.test.ts' "package.json in-memory settlement script points at focused test file"

contains "$BOOK" 'assertPostOnlyWouldRest' "book enforces POST_ONLY before matching"
contains "$BOOK" 'assertFokCanFullyFill' "book enforces FOK before matching"
contains "$BOOK" 'getCrossingLiquidity' "book computes crossing liquidity for FOK"

contains "$ENGINE" 'settleMatchedTrade' "in-memory engine settles matched trades downstream"
contains "$ENGINE" 'releaseBuyPriceImprovement' "in-memory engine releases buy-side price improvement downstream"
contains "$ENGINE" 'syncOrderStatusFromTrades' "in-memory engine syncs order statuses after fills"
contains "$ENGINE" 'reconcileTradeSettlement' "in-memory engine reconciles trade settlement"
contains "$ENGINE" 'releaseOrderOnCancel' "in-memory engine releases IOC/FOK remainder downstream"

contains "$SUBMIT" 'preferredEngine?: string | null;' "submit service accepts preferredEngine hint"
contains "$SUBMIT" 'selectMatchingEngine(input.preferredEngine as any);' "submit service resolves preferred engine through selector seam"

contains "$ORDERS" 'const preferredEngine = process.env.ALLOW_IN_MEMORY_MATCHING === "true"' "orders route gates preferred engine opt-in behind env flag"
contains "$ORDERS" 'req.get("x-matching-engine")' "orders route reads x-matching-engine header when allowed"
contains "$ORDERS" 'preferredEngine,' "orders route passes preferred engine into submit service"

contains "$TRADE" 'const preferredEngine = process.env.ALLOW_IN_MEMORY_MATCHING === "true"' "trade route gates preferred engine opt-in behind env flag"
contains "$TRADE" 'req.get("x-matching-engine")' "trade route reads x-matching-engine header when allowed"
contains "$TRADE" 'preferredEngine,' "trade route passes preferred engine into submit service"

contains "$INDEX" 'export * from "./in-memory-matching-engine";' "matching index re-exports in-memory engine"
contains "$INDEX" 'export * from "./select-engine";' "matching index re-exports selector"

contains "$TEST" 'book rejects POST_ONLY crosses and FOK underfill before matching' "4C tests cover TIF prechecks in the book"
contains "$TEST" 'in-memory engine creates trades and ledger settlement for matched fills' "4C tests cover downstream settlement integration"
contains "$TEST" 'submitLimitOrder selects preferred engine through the selector seam when no explicit engine is injected' "4C tests cover controlled preferred-engine selection"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 4C tests"
if (cd "$ROOT" && pnpm --filter api test:matching:in-memory-settlement); then
  pass "focused Phase 4C tests pass"
else
  fail "focused Phase 4C tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 4C checks passed."
