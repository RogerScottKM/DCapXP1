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
RUNTIME="$ROOT/apps/api/src/lib/runtime/runtime-status.ts"
WORKER="$ROOT/apps/api/src/workers/reconciliation.ts"
SERVER="$ROOT/apps/api/src/server.ts"
ROUTE="$ROOT/apps/api/src/routes/runtime-status.ts"
APP="$ROOT/apps/api/src/app.ts"
TEST_LIB="$ROOT/apps/api/test/runtime-status.lib.test.ts"
TEST_ROUTE="$ROOT/apps/api/test/runtime-status.routes.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$EVENTS" ] || fail "matching-events.ts exists"
[ -f "$RUNTIME" ] || fail "runtime-status.ts exists"
[ -f "$WORKER" ] || fail "reconciliation.ts exists"
[ -f "$SERVER" ] || fail "server.ts exists"
[ -f "$ROUTE" ] || fail "runtime-status.ts route exists"
[ -f "$APP" ] || fail "app.ts exists"
[ -f "$TEST_LIB" ] || fail "runtime-status.lib.test.ts exists"
[ -f "$TEST_ROUTE" ] || fail "runtime-status.routes.test.ts exists"

contains "$PKG" '"test:runtime:status"' "package.json includes runtime status test script"
contains "$PKG" 'vitest run test/runtime-status.lib.test.ts test/runtime-status.routes.test.ts' "package.json runtime status script points at focused test files"

contains "$EVENTS" '"RUNTIME_STATUS"' "matching events supports RUNTIME_STATUS"
contains "$EVENTS" '"RECONCILIATION_RESULT"' "matching events supports RECONCILIATION_RESULT"
contains "$EVENTS" '"HUMAN" | "AGENT" | "SYSTEM"' "matching events supports SYSTEM source"

contains "$RUNTIME" 'export function markRuntimeStarted' "runtime-status exports markRuntimeStarted"
contains "$RUNTIME" 'export function markRuntimeStopped' "runtime-status exports markRuntimeStopped"
contains "$RUNTIME" 'export function noteReconciliationRun' "runtime-status exports noteReconciliationRun"
contains "$RUNTIME" 'export function getRuntimeStatus' "runtime-status exports getRuntimeStatus"
contains "$RUNTIME" 'getSerializedLaneCount()' "runtime-status reads active serialized lanes"
contains "$RUNTIME" 'getMatchingEventCount()' "runtime-status reads matching event count"
contains "$RUNTIME" 'type: "RUNTIME_STATUS"' "runtime-status emits runtime status events"
contains "$RUNTIME" 'type: "RECONCILIATION_RESULT"' "runtime-status emits reconciliation result events"

contains "$WORKER" 'import { noteReconciliationRun } from "../lib/runtime/runtime-status";' "worker imports runtime reconciliation hook"
contains "$WORKER" 'noteReconciliationRun(allResults);' "worker records reconciliation status after each run"

contains "$SERVER" 'import { markRuntimeStarted, markRuntimeStopped } from "./lib/runtime/runtime-status";' "server imports runtime lifecycle helpers"
contains "$SERVER" 'markRuntimeStopped(signal);' "server marks runtime stopped during shutdown"
contains "$SERVER" 'markRuntimeStarted({' "server marks runtime started after boot"

contains "$ROUTE" 'requireAuth' "runtime-status route requires auth"
contains "$ROUTE" 'requireAdminRecentMfa()' "runtime-status route requires admin recent MFA"
contains "$ROUTE" 'getRuntimeStatus()' "runtime-status route returns runtime snapshot"

contains "$APP" 'import runtimeStatusRoutes from "./routes/runtime-status";' "app imports runtime status routes"
contains "$APP" 'app.use("/api/admin/runtime-status", runtimeStatusRoutes);' "app mounts runtime status routes"

contains "$TEST_LIB" 'tracks runtime start and stop with status snapshots' "runtime-status lib tests cover start/stop"
contains "$TEST_LIB" 'records reconciliation summaries and emits a reconciliation runtime event' "runtime-status lib tests cover reconciliation summary"
contains "$TEST_ROUTE" 'returns 401 without an authenticated session' "runtime-status route tests cover unauthenticated guard"
contains "$TEST_ROUTE" 'returns 403 for a non-admin request' "runtime-status route tests cover non-admin rejection"
contains "$TEST_ROUTE" 'returns the runtime status snapshot for an admin with recent MFA' "runtime-status route tests cover admin success"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 5A tests"
if (cd "$ROOT" && pnpm --filter api test:runtime:status); then
  pass "focused Phase 5A tests pass"
else
  fail "focused Phase 5A tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 5A checks passed."
