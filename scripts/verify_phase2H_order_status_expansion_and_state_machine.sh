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
SCHEMA="$ROOT/apps/api/prisma/schema.prisma"
MIGRATION="$ROOT/apps/api/prisma/migrations/20260412_order_status_expansion/migration.sql"
ORDER_STATE="$ROOT/apps/api/src/lib/ledger/order-state.ts"
ORDER_STATE_TEST="$ROOT/apps/api/test/ledger.order-state.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SCHEMA" ] || fail "schema.prisma exists"
[ -f "$MIGRATION" ] || fail "migration.sql exists"
[ -f "$ORDER_STATE" ] || fail "order-state.ts exists"
[ -f "$ORDER_STATE_TEST" ] || fail "ledger.order-state.test.ts exists"

contains "$PKG" '"test:ledger:order-state"' "package.json includes order-state test script"
contains "$PKG" 'vitest run test/ledger.order-state.test.ts' "package.json order-state script points at focused test file"

contains "$SCHEMA" 'enum OrderStatus {' "schema defines OrderStatus enum"
contains "$SCHEMA" 'PARTIALLY_FILLED' "schema includes PARTIALLY_FILLED"
contains "$SCHEMA" 'CANCEL_PENDING' "schema includes CANCEL_PENDING"
contains "$SCHEMA" 'CANCELLED' "schema keeps CANCELLED"

contains "$MIGRATION" "ADD VALUE IF NOT EXISTS 'PARTIALLY_FILLED'" "migration adds PARTIALLY_FILLED"
contains "$MIGRATION" "ADD VALUE IF NOT EXISTS 'CANCEL_PENDING'" "migration adds CANCEL_PENDING"

contains "$ORDER_STATE" 'export const ORDER_STATUS' "order-state exports ORDER_STATUS constants"
contains "$ORDER_STATE" 'assertValidTransition' "order-state exports transition validator"
contains "$ORDER_STATE" 'canReceiveFills' "order-state exports canReceiveFills"
contains "$ORDER_STATE" 'canCancel' "order-state exports canCancel"
contains "$ORDER_STATE" 'PARTIALLY_FILLED' "order-state references PARTIALLY_FILLED"
contains "$ORDER_STATE" 'CANCEL_PENDING' "order-state references CANCEL_PENDING"

contains "$ORDER_STATE_TEST" 'returns PARTIALLY_FILLED when partially executed' "order-state tests cover partial-fill derivation"
contains "$ORDER_STATE_TEST" 'preserves CANCEL_PENDING when no fills yet' "order-state tests cover cancel-pending derivation"
contains "$ORDER_STATE_TEST" 'allows CANCEL_PENDING → PARTIALLY_FILLED (fill race)' "order-state tests cover fill-race transition"
contains "$ORDER_STATE_TEST" 'CANCEL_PENDING can receive fills (race condition)' "order-state tests cover cancel-pending fills"
contains "$ORDER_STATE_TEST" 'CANCEL_PENDING cannot be cancelled again' "order-state tests cover cancel-pending cancel guard"

echo "[INFO] Running prisma generate"
if (cd "$ROOT/apps/api" && pnpm prisma generate); then
  pass "prisma generate passes"
else
  fail "prisma generate passes"
fi

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused order-state tests"
if (cd "$ROOT" && pnpm --filter api test:ledger:order-state); then
  pass "focused order-state tests pass"
else
  fail "focused order-state tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 2H checks passed."
