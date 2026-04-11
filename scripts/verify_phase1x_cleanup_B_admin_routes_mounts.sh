#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1"
  exit 1
}

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

ADMIN="$ROOT/apps/api/src/routes/admin.ts"
APP="$ROOT/apps/api/src/app.ts"
FLAGS="$ROOT/apps/api/src/routes/flags.ts"

check_contains "$ADMIN" 'requireRole("admin", "auditor")' "admin.ts requires admin/auditor role"
check_contains "$ADMIN" 'requireAdminRecentMfa(["admin", "auditor"])' "admin.ts requires recent admin MFA"
check_contains "$ADMIN" 'auditPrivilegedRequest(' "admin.ts audits privileged admin actions"
check_contains "$ADMIN" 'ADMIN_SYMBOL_SET' "admin.ts audits symbol updates"
check_contains "$ADMIN" 'ADMIN_RISK_SET' "admin.ts audits risk updates"
check_contains "$ADMIN" 'ADMIN_FLAGS_SET' "admin.ts audits flag updates"
check_contains "$ADMIN" 'featureFlags' "admin.ts subsumes feature flag controls"
check_contains "$ADMIN" 'symbolControl' "admin.ts includes symbol controls"
check_contains "$ADMIN" 'riskLimits' "admin.ts includes risk controls"

if [[ ! -f "$FLAGS" ]]; then
  pass "flags.ts removed as redundant"
else
  fail "flags.ts removed as redundant"
fi

check_contains "$APP" 'import adminRoutes from "./routes/admin";' "app.ts imports admin routes"
check_contains "$APP" 'import agenticRoutes from "./routes/agentic";' "app.ts imports agentic routes"
check_contains "$APP" 'import agentsRoutes from "./routes/agents";' "app.ts imports agents routes"
check_contains "$APP" 'import mandatesRoutes from "./routes/mandates";' "app.ts imports mandates routes"
check_contains "$APP" 'for (const prefix of ["/api/admin", "/admin"]) {' "app.ts mounts admin routes"
check_contains "$APP" 'for (const prefix of ["/api/v1/agents", "/v1/agents"]) {' "app.ts mounts agent routes"
check_contains "$APP" 'for (const prefix of ["/api/v1/mandates", "/v1/mandates"]) {' "app.ts mounts mandate routes"
check_contains "$APP" 'for (const prefix of ["/api/v1/ui", "/v1/ui"]) {' "app.ts mounts agentic UI routes"

if grep -Fq 'flagsRoutes' "$APP"; then
  fail "app.ts does not mount deprecated flags routes"
else
  pass "app.ts does not mount deprecated flags routes"
fi

echo
 echo "All Phase 1.x Cleanup B static checks passed."
