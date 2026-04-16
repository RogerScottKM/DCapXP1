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
not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq "$pattern" "$file"; then
    fail "$label"
  else
    pass "$label"
  fi
}

PKG="$ROOT/apps/api/package.json"
APP="$ROOT/apps/api/src/app.ts"
ROUTE="$ROOT/apps/api/src/routes/reconciliation.ts"
TEST="$ROOT/apps/api/test/reconciliation.routes.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$APP" ] || fail "app.ts exists"
[ -f "$ROUTE" ] || fail "reconciliation.ts exists"
[ -f "$TEST" ] || fail "reconciliation.routes.test.ts exists"

contains "$PKG" '"test:routes:reconciliation"' "package.json includes reconciliation route test script"
contains "$PKG" 'vitest run test/reconciliation.routes.test.ts' "package.json reconciliation route script points at focused test file"

contains "$APP" 'import reconciliationRoutes from "./routes/reconciliation";' "app.ts imports reconciliationRoutes"
contains "$APP" 'for (const prefix of ["/api/admin/reconciliation"]) { app.use(prefix, reconciliationRoutes); }' "app.ts mounts reconciliationRoutes only on /api/admin/reconciliation"
not_contains "$APP" 'for (const prefix of ["/admin/reconciliation"]) { app.use(prefix, reconciliationRoutes); }' "app.ts does not mount reconciliation routes on /admin/reconciliation"

contains "$ROUTE" 'router.post(' "reconciliation route defines a POST handler"
contains "$ROUTE" '"/run"' "reconciliation route exposes /run"
contains "$ROUTE" 'requireRole("ADMIN")' "reconciliation route requires ADMIN role"
contains "$ROUTE" 'requireRecentMfa()' "reconciliation route requires recent MFA"
contains "$ROUTE" 'auditPrivilegedRequest("RECONCILIATION_RUN_REQUESTED", "LEDGER")' "reconciliation route audits admin runs"
contains "$ROUTE" 'runReconciliation' "reconciliation route invokes runReconciliation"

contains "$TEST" 'POST /api/admin/reconciliation/run returns 401 without a session' "reconciliation route tests cover unauthenticated guard"
contains "$TEST" 'POST /api/admin/reconciliation/run returns 403 for a non-admin user' "reconciliation route tests cover non-admin rejection"
contains "$TEST" 'POST /api/admin/reconciliation/run returns 200 for an admin with recent MFA' "reconciliation route tests cover admin success"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused reconciliation route tests"
if (cd "$ROOT" && pnpm --filter api test:routes:reconciliation); then
  pass "focused reconciliation route tests pass"
else
  fail "focused reconciliation route tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 2K checks passed."
