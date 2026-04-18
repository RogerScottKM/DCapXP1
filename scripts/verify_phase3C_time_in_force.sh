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
MIGRATION="$ROOT/apps/api/prisma/migrations/20260416_phase3c_time_in_force/migration.sql"
HELPER="$ROOT/apps/api/src/lib/ledger/time-in-force.ts"
ORDERS="$ROOT/apps/api/src/routes/orders.ts"
TEST="$ROOT/apps/api/test/time-in-force.lib.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SCHEMA" ] || fail "schema.prisma exists"
[ -f "$MIGRATION" ] || fail "phase3c migration exists"
[ -f "$HELPER" ] || fail "time-in-force helper exists"
[ -f "$ORDERS" ] || fail "orders.ts exists"
[ -f "$TEST" ] || fail "time-in-force.lib.test.ts exists"

contains "$PKG" '"test:lib:time-in-force"' "package.json includes time-in-force test script"
contains "$PKG" 'vitest run test/time-in-force.lib.test.ts' "package.json TIF script points at focused test file"

contains "$SCHEMA" 'enum TimeInForce {' "schema adds TimeInForce enum"
contains "$SCHEMA" 'POST_ONLY' "schema includes POST_ONLY"
contains "$SCHEMA" 'timeInForce TimeInForce @default(GTC)' "schema adds Order.timeInForce with default"

contains "$MIGRATION" 'CREATE TYPE "TimeInForce"' "migration creates TimeInForce enum"
contains "$MIGRATION" 'ADD COLUMN IF NOT EXISTS "timeInForce" "TimeInForce"' "migration adds Order.timeInForce column"

contains "$HELPER" 'export const ORDER_TIF' "helper exports ORDER_TIF"
contains "$HELPER" 'normalizeTimeInForce' "helper exports normalizeTimeInForce"
contains "$HELPER" 'assertPostOnlyWouldRest' "helper exports POST_ONLY guard"
contains "$HELPER" 'assertFokCanFullyFill' "helper exports FOK guard"
contains "$HELPER" 'deriveTifRestingAction' "helper exports post-execution TIF action derivation"

contains "$ORDERS" 'import { normalizeTimeInForce } from "../lib/ledger/time-in-force";' "orders route imports TIF normalization helper"
contains "$ORDERS" 'timeInForce: z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional().default("GTC"),' "orders route accepts timeInForce in request schema"
contains "$ORDERS" 'const normalizedTimeInForce = normalizeTimeInForce(payload.timeInForce);' "orders route normalizes TIF"
contains "$ORDERS" 'timeInForce: normalizedTimeInForce as any,' "orders route persists timeInForce on create"
contains "$ORDERS" 'timeInForce: o.timeInForce,' "orders list response exposes timeInForce"
contains "$ORDERS" 'timeInForce: order.timeInForce,' "orders detail response exposes timeInForce"

contains "$TEST" 'defaults to GTC when the value is missing' "TIF tests cover default GTC"
contains "$TEST" 'rejects POST_ONLY orders that would cross' "TIF tests cover POST_ONLY rejection"
contains "$TEST" 'rejects FOK orders that cannot be fully filled' "TIF tests cover FOK rejection"
contains "$TEST" 'cancels IOC remainder after a partial execution' "TIF tests cover IOC remainder cancel behavior"

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

echo "[INFO] Running focused time-in-force tests"
if (cd "$ROOT" && pnpm --filter api test:lib:time-in-force); then
  pass "focused time-in-force tests pass"
else
  fail "focused time-in-force tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 3C checks passed."
