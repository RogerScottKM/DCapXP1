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
ALERTING="$ROOT/apps/api/src/lib/runtime/alerting.ts"
WORKER="$ROOT/apps/api/src/workers/reconciliation.ts"
ROUTE="$ROOT/apps/api/src/routes/admin-health.ts"
APP="$ROOT/apps/api/src/app.ts"
TEST_ALERT="$ROOT/apps/api/test/runtime-alerting.lib.test.ts"
TEST_ROUTE="$ROOT/apps/api/test/admin-health.routes.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$ALERTING" ] || fail "runtime alerting helper exists"
[ -f "$WORKER" ] || fail "reconciliation worker exists"
[ -f "$ROUTE" ] || fail "admin-health route exists"
[ -f "$APP" ] || fail "app.ts exists"
[ -f "$TEST_ALERT" ] || fail "runtime-alerting.lib.test.ts exists"
[ -f "$TEST_ROUTE" ] || fail "admin-health.routes.test.ts exists"

contains "$PKG" '"test:runtime:health"' "package.json includes runtime health test script"
contains "$PKG" 'vitest run test/runtime-alerting.lib.test.ts test/admin-health.routes.test.ts' "package.json runtime health script points at focused test files"

contains "$ALERTING" 'export function getAlertWebhookUrl()' "alerting helper exports webhook url getter"
contains "$ALERTING" 'export function isAlertingEnabled()' "alerting helper exports enabled check"
contains "$ALERTING" 'export async function dispatchRuntimeAlert' "alerting helper exports dispatch function"
contains "$ALERTING" 'ALERT_WEBHOOK_URL' "alerting helper supports ALERT_WEBHOOK_URL"

contains "$WORKER" 'import { dispatchRuntimeAlert } from "../lib/runtime/alerting";' "worker imports runtime alerting helper"
contains "$WORKER" 'type: "RECONCILIATION_FAILURE"' "worker dispatches reconciliation failure alerts"

contains "$ROUTE" 'router.get("/", requireAdminRecentMfa()' "admin-health route requires admin recent MFA"
contains "$ROUTE" 'getMatchingEventListenerCount()' "admin-health route returns subscriber count"
contains "$ROUTE" 'listMatchingEvents(50)' "admin-health route reads recent events"
contains "$ROUTE" 'lastReconciliation' "admin-health route returns last reconciliation summary"

contains "$APP" 'import adminHealthRoutes from "./routes/admin-health";' "app imports admin-health routes"
contains "$APP" 'app.use("/api/admin/health", adminHealthRoutes);' "app mounts admin-health routes"

contains "$TEST_ALERT" 'skips dispatch when no webhook is configured' "5C tests cover skipped alert dispatch"
contains "$TEST_ALERT" 'posts alert payloads when a webhook is configured' "5C tests cover webhook posting"
contains "$TEST_ROUTE" 'returns 401 without an authenticated session' "5C tests cover unauthenticated admin health"
contains "$TEST_ROUTE" 'returns 403 for a non-admin request' "5C tests cover non-admin rejection"
contains "$TEST_ROUTE" 'returns admin health including runtime and subscriber metrics' "5C tests cover admin health success"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 5C tests"
if (cd "$ROOT" && pnpm --filter api test:runtime:health); then
  pass "focused Phase 5C tests pass"
else
  fail "focused Phase 5C tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 5C checks passed."
