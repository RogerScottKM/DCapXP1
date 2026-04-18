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
ENGINE_PORT="$ROOT/apps/api/src/lib/matching/engine-port.ts"
DB_ENGINE="$ROOT/apps/api/src/lib/matching/db-matching-engine.ts"
SUBMIT="$ROOT/apps/api/src/lib/matching/submit-limit-order.ts"
ORDERS="$ROOT/apps/api/src/routes/orders.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"
TEST="$ROOT/apps/api/test/order-submission-unification.test.ts"
INDEX="$ROOT/apps/api/src/lib/matching/index.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$ENGINE_PORT" ] || fail "engine-port.ts exists"
[ -f "$DB_ENGINE" ] || fail "db-matching-engine.ts exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$ORDERS" ] || fail "orders.ts exists"
[ -f "$TRADE" ] || fail "trade.ts exists"
[ -f "$TEST" ] || fail "order-submission-unification.test.ts exists"
[ -f "$INDEX" ] || fail "matching index exists"

contains "$PKG" '"test:matching:submission"' "package.json includes matching submission test script"
contains "$PKG" 'vitest run test/order-submission-unification.test.ts' "package.json matching submission script points at focused test file"

contains "$ENGINE_PORT" 'export interface MatchingEnginePort' "engine-port exports MatchingEnginePort"
contains "$DB_ENGINE" 'class DbMatchingEngine' "db adapter defines DbMatchingEngine"
contains "$DB_ENGINE" 'executeLimitOrderAgainstBook' "db adapter uses executeLimitOrderAgainstBook"
contains "$DB_ENGINE" 'reconcileOrderExecution' "db adapter uses reconcileOrderExecution"
contains "$SUBMIT" 'export async function submitLimitOrder' "shared service exports submitLimitOrder"
contains "$SUBMIT" 'reserveOrderOnPlacement' "shared service reserves funds before engine dispatch"
contains "$SUBMIT" 'engine.executeLimitOrder' "shared service dispatches through matching engine boundary"
contains "$SUBMIT" 'normalizeTimeInForce' "shared service normalizes time-in-force"

contains "$ORDERS" 'import { submitLimitOrder } from "../lib/matching/submit-limit-order";' "orders route imports shared submission service"
contains "$ORDERS" 'source: "HUMAN"' "orders route submits through shared HUMAN boundary"

contains "$TRADE" 'import { submitLimitOrder } from "../lib/matching/submit-limit-order";' "trade route imports shared submission service"
contains "$TRADE" 'source: "AGENT"' "trade route submits through shared AGENT boundary"
contains "$TRADE" 'await bumpOrdersPlaced(' "trade route still bumps mandate usage after shared submission"

contains "$INDEX" 'export * from "./submit-limit-order";' "matching index re-exports submit service"

contains "$TEST" 'db matching engine delegates to execution and reconciliation helpers' "unification tests cover db adapter delegation"
contains "$TEST" 'submitLimitOrder creates, reserves, and dispatches through the shared engine boundary' "unification tests cover shared submission service"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 4A tests"
if (cd "$ROOT" && pnpm --filter api test:matching:submission); then
  pass "focused Phase 4A tests pass"
else
  fail "focused Phase 4A tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 4A checks passed."
