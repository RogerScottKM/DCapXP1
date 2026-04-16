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
APP="$ROOT/apps/api/src/app.ts"
ORDERS="$ROOT/apps/api/src/routes/orders.ts"
TEST="$ROOT/apps/api/test/orders.routes.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$APP" ] || fail "app.ts exists"
[ -f "$ORDERS" ] || fail "orders.ts exists"
[ -f "$TEST" ] || fail "orders.routes.test.ts exists"

contains "$PKG" '"test:routes:orders"' "package.json includes orders route test script"
contains "$PKG" 'vitest run test/orders.routes.test.ts' "package.json orders route script points at focused test file"

contains "$APP" 'import ordersRoutes from "./routes/orders";' "app imports orders route"
contains "$APP" 'app.use("/api/orders", ordersRoutes);' "app mounts /api/orders"
if grep -Fq '/api/v1/orders' "$APP"; then
  fail "app does not mount /api/v1/orders to avoid route collision"
else
  pass "app does not mount /api/v1/orders to avoid route collision"
fi

contains "$ORDERS" 'router.use(requireAuth);' "orders router requires session auth"
contains "$ORDERS" 'requireRecentMfa()' "orders router requires recent MFA for privileged actions"
contains "$ORDERS" 'requireLiveModeEligible()' "orders router enforces live-mode eligibility"
contains "$ORDERS" 'simpleRateLimit' "orders router uses rate limiting"
contains "$ORDERS" 'auditPrivilegedRequest("ORDER_PLACE_REQUESTED"' "orders router audits order placement"
contains "$ORDERS" 'auditPrivilegedRequest("ORDER_CANCEL_REQUESTED"' "orders router audits order cancellation"
contains "$ORDERS" 'executeLimitOrderAgainstBook' "orders router executes against book"
contains "$ORDERS" 'releaseOrderOnCancel' "orders router releases held funds on cancel"
contains "$ORDERS" 'canCancel' "orders router uses canCancel state guard"
contains "$ORDERS" 'ORDER_STATUS.CANCELLED' "orders router uses ORDER_STATUS.CANCELLED"

contains "$TEST" 'returns 401 without session auth' "orders route tests cover unauthenticated access"
contains "$TEST" 'lists only the authenticated user orders' "orders route tests cover authenticated listing"
contains "$TEST" "rejects fetching another user order detail" "orders route tests cover ownership guard"
contains "$TEST" 'allows cancelling a PARTIALLY_FILLED order for the current user' "orders route tests cover partially-filled cancel"

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
