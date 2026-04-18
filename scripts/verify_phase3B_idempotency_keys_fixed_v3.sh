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
MIGRATION="$ROOT/apps/api/prisma/migrations/20260416_phase3b_idempotency_keys/migration.sql"
HELPER="$ROOT/apps/api/src/lib/idempotency.ts"
ORDERS="$ROOT/apps/api/src/routes/orders.ts"
TEST="$ROOT/apps/api/test/idempotency.lib.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SCHEMA" ] || fail "schema.prisma exists"
[ -f "$MIGRATION" ] || fail "phase3b migration exists"
[ -f "$HELPER" ] || fail "idempotency helper exists"
[ -f "$ORDERS" ] || fail "orders.ts exists"
[ -f "$TEST" ] || fail "idempotency.lib.test.ts exists"

contains "$PKG" '"test:lib:idempotency"' "package.json includes idempotency lib test script"
contains "$PKG" 'vitest run test/idempotency.lib.test.ts' "package.json idempotency script points at focused test file"

contains "$SCHEMA" 'model IdempotencyKey {' "schema adds IdempotencyKey model"
contains "$SCHEMA" '@@unique([ownerType, ownerId, scope, key])' "schema defines unique idempotency compound key"
contains "$SCHEMA" 'responseBody   Json?' "schema stores replayable response body"

contains "$MIGRATION" 'CREATE TABLE IF NOT EXISTS "IdempotencyKey"' "migration creates IdempotencyKey table"
contains "$MIGRATION" 'CREATE UNIQUE INDEX IF NOT EXISTS "IdempotencyKey_ownerType_ownerId_scope_key_key"' "migration creates unique idempotency index"

contains "$HELPER" 'export function withIdempotency' "helper exports withIdempotency"
contains "$HELPER" 'Idempotency key reuse with different payload.' "helper rejects same-key different-payload reuse"
contains "$HELPER" 'Idempotency request is already in progress.' "helper handles in-flight duplicates"

contains "$ORDERS" 'import { withIdempotency } from "../lib/idempotency";' "orders route imports idempotency helper"
contains "$ORDERS" 'withIdempotency("HUMAN_ORDER_PLACE"' "orders route wraps placement with idempotency"
contains "$ORDERS" 'withIdempotency("HUMAN_ORDER_CANCEL"' "orders route wraps cancel with idempotency"

contains "$TEST" 'replays the stored response for the same key and same payload' "idempotency tests cover same-key replay"
contains "$TEST" 'rejects the same key reused with a different payload' "idempotency tests cover same-key mismatch rejection"
contains "$TEST" 'runs normally when no idempotency key is provided' "idempotency tests cover optional key behavior"

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

echo "[INFO] Running focused idempotency tests"
if (cd "$ROOT" && pnpm --filter api test:lib:idempotency); then
  pass "focused idempotency tests pass"
else
  fail "focused idempotency tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 3B checks passed."
