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
SUBMIT="$ROOT/apps/api/src/lib/matching/submit-limit-order.ts"
ORDERS="$ROOT/apps/api/src/routes/orders.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"
TEST="$ROOT/apps/api/test/in-memory-settlement-integration.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$ORDERS" ] || fail "orders.ts exists"
[ -f "$TRADE" ] || fail "trade.ts exists"
[ -f "$TEST" ] || fail "in-memory-settlement-integration.test.ts exists"

contains "$PKG" '"test:matching:in-memory-settlement"' "package.json includes in-memory settlement test script"
contains "$PKG" 'vitest run test/in-memory-settlement-integration.test.ts' "package.json in-memory settlement script points at focused test file"

contains "$SUBMIT" 'preferredEngine?: string | null;' "submit service accepts preferredEngine hint"
contains "$SUBMIT" 'selectMatchingEngine(input.preferredEngine as any)' "submit service resolves preferred engine through selector seam"

contains "$ORDERS" 'ALLOW_IN_MEMORY_MATCHING === "true"' "orders route gates preferred engine opt-in behind env flag"
contains "$ORDERS" 'x-matching-engine' "orders route reads matching-engine header when allowed"
contains "$ORDERS" 'preferredEngine,' "orders route passes preferred engine into submit service"

contains "$TRADE" 'ALLOW_IN_MEMORY_MATCHING === "true"' "trade route gates preferred engine opt-in behind env flag"
contains "$TRADE" 'x-matching-engine' "trade route reads matching-engine header when allowed"
contains "$TRADE" 'preferredEngine,' "trade route passes preferred engine into submit service"

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
echo "All Phase 4C fix checks passed."
