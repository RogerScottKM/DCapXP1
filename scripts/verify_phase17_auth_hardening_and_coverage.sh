#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }
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

PACKAGE_JSON="$ROOT/apps/api/package.json"
VITEST_CONFIG="$ROOT/apps/api/vitest.config.ts"
REQUIRE_AUTH="$ROOT/apps/api/src/middleware/require-auth.ts"
AUTH_SERVICE="$ROOT/apps/api/src/modules/auth/auth.service.ts"
TEST_AUTH_SERVICE="$ROOT/apps/api/test/auth.service.audit.test.ts"
TEST_REQUIRE_AUTH="$ROOT/apps/api/test/require-auth.audit.test.ts"

check_contains "$PACKAGE_JSON" '"vitest"' "package.json includes vitest"
check_contains "$PACKAGE_JSON" '"supertest"' "package.json includes supertest"
check_contains "$PACKAGE_JSON" '"test": "vitest run"' "package.json includes test script"
check_contains "$PACKAGE_JSON" '"test:auth":' "package.json includes auth test script"
check_contains "$VITEST_CONFIG" 'defineConfig' "vitest config exists"

check_contains "$REQUIRE_AUTH" 'recordSecurityAudit' "require-auth.ts imports security audit helper"
check_contains "$REQUIRE_AUTH" 'AUTHZ_UNAUTHENTICATED_DENIED' "require-auth.ts audits unauthenticated denials"
check_contains "$REQUIRE_AUTH" 'AUTHZ_ROLE_DENIED' "require-auth.ts audits role denials"
check_contains "$REQUIRE_AUTH" 'AUTHZ_MFA_REQUIRED_DENIED' "require-auth.ts audits MFA denials"
check_contains "$REQUIRE_AUTH" 'AUTHZ_ADMIN_MFA_REQUIRED_DENIED' "require-auth.ts audits admin MFA denials"
check_contains "$REQUIRE_AUTH" 'LIVE_MODE_DENIED' "require-auth.ts audits LIVE mode denials"

check_contains "$AUTH_SERVICE" 'recordSecurityAudit' "auth.service.ts imports security audit helper"
check_contains "$AUTH_SERVICE" 'AUTH_LOGIN_SUCCEEDED' "auth.service.ts audits login success"
check_contains "$AUTH_SERVICE" 'AUTH_LOGIN_FAILED' "auth.service.ts audits login failure"
check_contains "$AUTH_SERVICE" 'AUTH_LOGOUT' "auth.service.ts audits logout"
check_contains "$AUTH_SERVICE" 'AUTH_PASSWORD_RESET_REQUESTED' "auth.service.ts audits password reset requests"
check_contains "$AUTH_SERVICE" 'AUTH_PASSWORD_RESET_COMPLETED' "auth.service.ts audits password reset completion"
check_contains "$AUTH_SERVICE" 'AUTH_OTP_SENT' "auth.service.ts audits OTP send"
check_contains "$AUTH_SERVICE" 'AUTH_OTP_VERIFIED' "auth.service.ts audits OTP verification"

check_contains "$TEST_AUTH_SERVICE" 'AUTH_LOGIN_SUCCEEDED' "auth service test covers login success audit"
check_contains "$TEST_AUTH_SERVICE" 'AUTH_LOGIN_FAILED' "auth service test covers login failure audit"
check_contains "$TEST_AUTH_SERVICE" 'AUTH_LOGOUT' "auth service test covers logout audit"
check_contains "$TEST_REQUIRE_AUTH" 'AUTHZ_MFA_REQUIRED_DENIED' "require-auth test covers MFA denial audit"
check_contains "$TEST_REQUIRE_AUTH" 'AUTHZ_ROLE_DENIED' "require-auth test covers role denial audit"
check_contains "$TEST_REQUIRE_AUTH" 'LIVE_MODE_DENIED' "require-auth test covers LIVE denial audit"

echo

echo "All Phase 1.7 static checks passed."
