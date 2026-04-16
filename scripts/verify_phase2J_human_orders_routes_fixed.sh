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
ROUTE="$ROOT/apps/api/src/routes/orders.ts"
TEST="$ROOT/apps/api/test/orders.routes.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$APP" ] || fail "app.ts exists"
[ -f "$ROUTE" ] || fail "orders.ts exists"
[ -f "$TEST" ] || fail "orders.routes.test.ts exists"

contains "$PKG" '"test:routes:orders"' "package.json includes orders route test script"
contains "$PKG" 'vitest run test/orders.routes.test.ts' "package.json orders route script points at focused test file"

contains "$APP" 'import ordersRoutes from "./routes/orders";' "app.ts imports ordersRoutes"
contains "$APP" 'for (const prefix of ["/api/orders"]) { app.use(prefix, ordersRoutes); }' "app.ts mounts ordersRoutes only on /api/orders"
not_contains "$APP" '/api/v1/orders' "app.ts does not mount human routes on /api/v1/orders"

contains "$ROUTE" 'router.use(requireAuth);' "orders route requires session auth"
contains "$ROUTE" 'requireRecentMfa()' "orders route requires recent MFA for writes"
contains "$ROUTE" 'requireLiveModeEligible()' "orders route checks LIVE mode eligibility"
contains "$ROUTE" 'auditPrivilegedRequest("ORDER_PLACE_REQUESTED", "ORDER")' "orders route audits placements"
contains "$ROUTE" 'auditPrivilegedRequest("ORDER_CANCEL_REQUESTED", "ORDER"' "orders route audits cancels"

contains "$TEST" 'GET /api/orders returns 401 without a session' "orders route tests cover list auth guard"
contains "$TEST" 'POST /api/orders returns 401 without a session' "orders route tests cover place auth guard"
contains "$TEST" 'GET /api/orders/:id returns 401 without a session' "orders route tests cover detail auth guard"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused orders route tests"
if (cd "$ROOT" && pnpm --filter api test:routes:orders); then
  pass "focused orders route tests pass"
else
  fail "focused orders route tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 2J checks passed."
