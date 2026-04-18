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
EVENTS="$ROOT/apps/api/src/lib/matching/matching-events.ts"
ROUTE="$ROOT/apps/api/src/routes/matching-events.ts"
APP="$ROOT/apps/api/src/app.ts"
SUBMIT="$ROOT/apps/api/src/lib/matching/submit-limit-order.ts"
INDEX="$ROOT/apps/api/src/lib/matching/index.ts"
TEST="$ROOT/apps/api/test/matching-events.stream.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$EVENTS" ] || fail "matching-events.ts exists"
[ -f "$ROUTE" ] || fail "matching-events.ts route exists"
[ -f "$APP" ] || fail "app.ts exists"
[ -f "$SUBMIT" ] || fail "submit-limit-order.ts exists"
[ -f "$INDEX" ] || fail "matching index exists"
[ -f "$TEST" ] || fail "matching-events.stream.test.ts exists"

contains "$PKG" '"test:matching:stream"' "package.json includes matching stream test script"
contains "$PKG" 'vitest run test/matching-events.stream.test.ts' "package.json matching stream script points at focused test file"

contains "$EVENTS" 'export type MatchingEventEnvelope' "matching-events exports event envelope type"
contains "$EVENTS" 'subscribeMatchingEvents(listener: MatchingEventListener)' "matching-events exports live subscription helper"
contains "$EVENTS" 'getMatchingEventListenerCount()' "matching-events exports listener count helper"
contains "$EVENTS" 'emitMatchingEvent(event: MatchingEvent): MatchingEventEnvelope' "matching-events emits envelopes with ids"

contains "$ROUTE" 'router.get("/recent"' "matching events route exposes /recent"
contains "$ROUTE" 'router.get("/stream"' "matching events route exposes /stream"
contains "$ROUTE" 'text/event-stream' "matching events stream uses SSE content type"
contains "$ROUTE" 'buildSseEventFrame' "matching events route exports SSE frame helper"

contains "$APP" 'import matchingEventsRoutes from "./routes/matching-events";' "app imports matching events routes"
contains "$APP" 'app.use("/api/market/events", matchingEventsRoutes);' "app mounts matching events routes"

contains "$SUBMIT" 'const emittedEvents = emitMatchingEvents(events);' "submit service stores emitted event envelopes"
contains "$SUBMIT" 'events: emittedEvents,' "submit service returns emitted event envelopes"

contains "$INDEX" 'export * from "./matching-events";' "matching index re-exports matching events helper"

contains "$TEST" 'matching event subscriptions receive emitted envelopes with ids' "4F tests cover event subscriptions"
contains "$TEST" 'recent route returns filtered websocket-ready events' "4F tests cover recent route"
contains "$TEST" 'buildSseEventFrame formats websocket-ready matching events for SSE' "4F tests cover SSE frame formatting"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 4F tests"
if (cd "$ROOT" && pnpm --filter api test:matching:stream); then
  pass "focused Phase 4F tests pass"
else
  fail "focused Phase 4F tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 4F checks passed."
