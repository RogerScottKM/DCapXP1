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

ROUTE="$ROOT/apps/api/src/routes/matching-events.ts"
APP="$ROOT/apps/api/src/app.ts"
TEST="$ROOT/apps/api/test/matching-events.stream.test.ts"
PKG="$ROOT/apps/api/package.json"

[ -f "$ROUTE" ] || fail "matching-events route exists"
[ -f "$APP" ] || fail "app.ts exists"
[ -f "$TEST" ] || fail "matching-events.stream.test.ts exists"
[ -f "$PKG" ] || fail "package.json exists"

contains "$ROUTE" 'return `id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;' "route builds escaped SSE event frames"
contains "$ROUTE" 'res.write(`event: snapshot\ndata: ${JSON.stringify({ events: snapshot })}\n\n`);' "route writes escaped SSE snapshot frame"
contains "$ROUTE" 'res.write(": keep-alive\n\n");' "route writes escaped keep-alive frame"
contains "$ROUTE" 'router.get("/recent"' "route exposes /recent"
contains "$ROUTE" 'router.get("/stream"' "route exposes /stream"

contains "$APP" 'app.use("/api/market/events", matchingEventsRoutes);' "app mounts matching events routes"
contains "$PKG" '"test:matching:stream"' "package.json still includes matching stream test script"

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
echo "All Phase 4F route-fix checks passed."
