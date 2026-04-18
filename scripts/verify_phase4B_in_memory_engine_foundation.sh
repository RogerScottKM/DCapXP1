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
SELECTOR="$ROOT/apps/api/src/lib/matching/select-engine.ts"
SUBMIT="$ROOT/apps/api/src/lib/matching/submit-limit-order.ts"
INDEX="$ROOT/apps/api/src/lib/matching/index.ts"
TEST="$ROOT/apps/api/test/in-memory-matching-engine.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$BOOK" ] || fail "in-memory-order-book.ts exists"
[ -f "$ENGINE" ] || fail "in-memory-matching-engine.ts exists"
[ -f "$SELECTOR" ] || fail "select-engine.ts exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$INDEX" ] || fail "matching index exists"
[ -f "$TEST" ] || fail "in-memory-matching-engine.test.ts exists"

contains "$PKG" '"test:matching:in-memory"' "package.json includes in-memory matching test script"
contains "$PKG" 'vitest run test/in-memory-matching-engine.test.ts' "package.json in-memory matching script points at focused test file"

contains "$BOOK" 'export class InMemoryOrderBook' "book module exports InMemoryOrderBook"
contains "$BOOK" 'matchIncoming' "book module supports matchIncoming"
contains "$BOOK" 'deriveTifRestingAction' "book module applies TIF resting action"
contains "$ENGINE" 'class InMemoryMatchingEngine' "engine module defines InMemoryMatchingEngine"
contains "$ENGINE" 'this.getBook(order.symbol, order.mode)' "engine routes orders into per-symbol-mode books"
contains "$ENGINE" 'Experimental in-memory engine foundation; ledger settlement is not yet integrated.' "engine clearly marks experimental reconciliation note"
contains "$SELECTOR" 'export function selectMatchingEngine' "selector exports selectMatchingEngine"
contains "$SELECTOR" 'return inMemoryMatchingEngine;' "selector can choose in-memory engine"
contains "$SUBMIT" 'const selectedEngine = engine ?? selectMatchingEngine();' "submit service uses selector seam when no engine is provided"

contains "$INDEX" 'export * from "./in-memory-order-book";' "matching index re-exports order book"
contains "$INDEX" 'export * from "./in-memory-matching-engine";' "matching index re-exports in-memory engine"
contains "$INDEX" 'export * from "./select-engine";' "matching index re-exports selector"

contains "$TEST" 'matches BUY takers against the best asks using price-time priority' "4B tests cover price-time in-memory matching"
contains "$TEST" 'rests remaining GTC quantity on the book but cancels IOC remainder' "4B tests cover TIF behavior in the book"
contains "$TEST" 'selectMatchingEngine defaults to DB and can explicitly choose in-memory' "4B tests cover engine selector"
contains "$TEST" 'in-memory engine stages and matches orders across successive submissions' "4B tests cover staged successive submissions"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 4B tests"
if (cd "$ROOT" && pnpm --filter api test:matching:in-memory); then
  pass "focused Phase 4B tests pass"
else
  fail "focused Phase 4B tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 4B checks passed."
