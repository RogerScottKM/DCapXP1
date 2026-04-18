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
MIGRATION="$ROOT/apps/api/prisma/migrations/20260418_phase5e_matching_event_history/migration.sql"
EVENTS="$ROOT/apps/api/src/lib/matching/matching-events.ts"
SUBMIT="$ROOT/apps/api/src/lib/matching/submit-limit-order.ts"
ROUTE="$ROOT/apps/api/src/routes/matching-events.ts"
TEST_PERSIST="$ROOT/apps/api/test/matching-events.persistence.test.ts"
TEST_REPLAY="$ROOT/apps/api/test/matching-events.replay.routes.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SCHEMA" ] || fail "schema.prisma exists"
[ -f "$MIGRATION" ] || fail "phase5e migration exists"
[ -f "$EVENTS" ] || fail "matching-events.ts exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$ROUTE" ] || fail "matching-events route exists"
[ -f "$TEST_PERSIST" ] || fail "matching-events.persistence.test.ts exists"
[ -f "$TEST_REPLAY" ] || fail "matching-events.replay.routes.test.ts exists"

contains "$PKG" '"test:matching:durable-events"' "package.json includes durable-events test script"
contains "$PKG" 'vitest run test/matching-events.persistence.test.ts test/matching-events.replay.routes.test.ts' "package.json durable-events script points at focused test files"

contains "$SCHEMA" 'model MatchingEvent {' "schema adds MatchingEvent model"
contains "$SCHEMA" 'eventId   Int      @unique' "schema stores unique replayable event id"
contains "$SCHEMA" '@@index([symbol, mode, eventId])' "schema indexes symbol/mode/eventId"

contains "$MIGRATION" 'CREATE TABLE "MatchingEvent"' "migration creates MatchingEvent table"
contains "$MIGRATION" '"eventId" INTEGER NOT NULL UNIQUE' "migration creates unique eventId"
contains "$MIGRATION" '"payload" JSONB NOT NULL' "migration stores payload as JSONB"

contains "$EVENTS" 'export async function persistMatchingEventEnvelope' "matching-events exports single-event persistence"
contains "$EVENTS" 'export async function persistMatchingEventEnvelopes' "matching-events exports bulk persistence"
contains "$EVENTS" 'export async function listPersistedMatchingEvents' "matching-events exports durable replay helper"
contains "$EVENTS" 'db.matchingEvent.upsert' "matching-events persists via Prisma upsert"
contains "$EVENTS" 'db.matchingEvent.findMany' "matching-events replays persisted events via Prisma"

contains "$SUBMIT" 'persistMatchingEventEnvelopes' "submit service persists emitted event envelopes"
contains "$SUBMIT" 'await persistMatchingEventEnvelopes(emittedEvents, tx as any);' "submit service persists durable event history in transaction"

contains "$ROUTE" 'router.get("/replay"' "matching-events route exposes /replay"
contains "$ROUTE" 'listPersistedMatchingEvents({' "matching-events route calls durable replay helper"

contains "$TEST_PERSIST" 'persists event envelopes idempotently by eventId' "5E tests cover idempotent persistence"
contains "$TEST_PERSIST" 'persists multiple event envelopes and replays them with filters' "5E tests cover persisted replay filtering"
contains "$TEST_REPLAY" 'returns durable replay events filtered by symbol/mode/event id' "5E tests cover replay route"

echo "[INFO] Running prisma generate"
if (cd "$ROOT" && pnpm --filter api prisma); then
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

echo "[INFO] Running focused Phase 5E tests"
if (cd "$ROOT" && pnpm --filter api test:matching:durable-events); then
  pass "focused Phase 5E tests pass"
else
  fail "focused Phase 5E tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 5E checks passed."
