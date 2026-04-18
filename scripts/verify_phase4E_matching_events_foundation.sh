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
EVENTS="$ROOT/apps/api/src/lib/matching/matching-events.ts"
INDEX="$ROOT/apps/api/src/lib/matching/index.ts"
TEST="$ROOT/apps/api/test/matching-events.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$BOOK" ] || fail "in-memory-order-book.ts exists"
[ -f "$ENGINE" ] || fail "in-memory-matching-engine.ts exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$EVENTS" ] || fail "matching-events.ts exists"
[ -f "$INDEX" ] || fail "matching index exists"
[ -f "$TEST" ] || fail "matching-events.test.ts exists"

contains "$PKG" '"test:matching:events"' "package.json includes matching events test script"
contains "$PKG" 'vitest run test/matching-events.test.ts' "package.json matching events script points at focused test file"

contains "$BOOK" 'export type InMemoryBookDelta' "book exports InMemoryBookDelta"
contains "$BOOK" 'getBookDelta(symbol: string): InMemoryBookDelta' "book can derive book deltas"
contains "$BOOK" 'bookDelta: this.getBookDelta(input.symbol)' "book returns websocket-ready delta from matchIncoming"

contains "$ENGINE" 'bookDelta: bookExecution.bookDelta,' "in-memory engine passes through book deltas in execution output"

contains "$EVENTS" 'export type MatchingEvent' "matching-events exports event type"
contains "$EVENTS" 'emitMatchingEvents(events: MatchingEvent[])' "matching-events exports batch emitter"
contains "$EVENTS" 'listMatchingEvents(limit = 100)' "matching-events exports event listing"
contains "$EVENTS" 'buildMatchingEventsFromSubmission' "matching-events exports submission event builder"
contains "$EVENTS" '"BOOK_DELTA"' "matching-events supports BOOK_DELTA"

contains "$SUBMIT" 'buildMatchingEventsFromSubmission' "submit service builds websocket-ready events"
contains "$SUBMIT" 'emitMatchingEvents(events);' "submit service emits websocket-ready events"
contains "$SUBMIT" 'events,' "submit service returns emitted events in response"

contains "$INDEX" 'export * from "./matching-events";' "matching index re-exports matching events helper"

contains "$TEST" 'in-memory order book returns a websocket-ready book delta' "4E tests cover book delta generation"
contains "$TEST" 'buildMatchingEventsFromSubmission derives accepted, fill, filled, and book-delta events' "4E tests cover event derivation"
contains "$TEST" 'submitLimitOrder emits websocket-ready events through the shared boundary' "4E tests cover submission event emission"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 4E tests"
if (cd "$ROOT" && pnpm --filter api test:matching:events); then
  pass "focused Phase 4E tests pass"
else
  fail "focused Phase 4E tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 4E checks passed."
