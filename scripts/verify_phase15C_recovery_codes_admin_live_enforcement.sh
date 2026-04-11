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

SCHEMA="$ROOT/apps/api/prisma/schema.prisma"
MIGRATION="$ROOT/apps/api/prisma/migrations/20260410_phase15c_recovery_codes/migration.sql"
MFA_SERVICE="$ROOT/apps/api/src/modules/auth/mfa.service.ts"
AUTH_CONTROLLER="$ROOT/apps/api/src/modules/auth/auth.controller.ts"
AUTH_ROUTES="$ROOT/apps/api/src/modules/auth/auth.routes.ts"
REQUIRE_AUTH="$ROOT/apps/api/src/middleware/require-auth.ts"
LEGACY_AUTH="$ROOT/apps/api/src/middleware/auth.ts"

check_contains "$SCHEMA" "model MfaRecoveryCode" "schema.prisma adds MfaRecoveryCode model"
check_contains "$SCHEMA" "codeHash" "schema.prisma includes recovery code hash"
check_contains "$SCHEMA" "@@index([userId, consumedAt])" "schema.prisma indexes recovery codes"

if grep -Eq 'CREATE TABLE( IF NOT EXISTS)? "MfaRecoveryCode"' "$MIGRATION"; then
  pass "migration creates MfaRecoveryCode table"
else
  fail "migration creates MfaRecoveryCode table"
fi

if grep -Eq 'CREATE UNIQUE INDEX( IF NOT EXISTS)? "MfaRecoveryCode_codeHash_key"' "$MIGRATION"; then
  pass "migration creates recovery code unique index"
else
  fail "migration creates recovery code unique index"
fi

if grep -Eq 'CREATE INDEX( IF NOT EXISTS)? "MfaRecoveryCode_userId_consumedAt_idx"' "$MIGRATION"; then
  pass "migration creates recovery code lookup index"
else
  fail "migration creates recovery code lookup index"
fi

check_contains "$MFA_SERVICE" "regenerateRecoveryCodes" "mfa.service.ts defines recovery code regeneration"
check_contains "$MFA_SERVICE" "challengeRecoveryCode" "mfa.service.ts defines recovery code challenge"
check_contains "$MFA_SERVICE" "generateRecoveryCodes" "mfa.service.ts generates recovery codes"
check_contains "$MFA_SERVICE" "codeHash" "mfa.service.ts hashes recovery codes"
if grep -Eq 'recovery_code|mfaMethod' "$MFA_SERVICE"; then
  pass "mfa.service.ts records recovery-code MFA method"
else
  fail "mfa.service.ts records recovery-code MFA method"
fi

check_contains "$AUTH_CONTROLLER" "regenerateRecoveryCodes" "auth.controller.ts exports regenerateRecoveryCodes"
check_contains "$AUTH_CONTROLLER" "challengeRecoveryCode" "auth.controller.ts exports challengeRecoveryCode"

check_contains "$AUTH_ROUTES" '/auth/mfa/recovery-codes/regenerate' "auth.routes.ts mounts recovery code regenerate route"
check_contains "$AUTH_ROUTES" '/auth/mfa/recovery-codes/challenge' "auth.routes.ts mounts recovery code challenge route"
check_contains "$AUTH_ROUTES" 'requireRecentMfa' "auth.routes.ts protects recovery regeneration with recent MFA"

check_contains "$REQUIRE_AUTH" "export function requireAdminRecentMfa" "require-auth.ts exports requireAdminRecentMfa"
check_contains "$REQUIRE_AUTH" "export function requireLiveModeEligible" "require-auth.ts exports requireLiveModeEligible"
check_contains "$REQUIRE_AUTH" 'code: "LIVE_MODE_NOT_ALLOWED"' "require-auth.ts blocks LIVE mode without eligibility"
if grep -Ei 'requireRole\(["'"'"']admin["'"'"']\s*,\s*["'"'"']auditor["'"'"']\)|requireRole\(["'"'"']ADMIN["'"'"']\s*,\s*["'"'"']AUDITOR["'"'"']\)|admin.*auditor|auditor.*admin' "$REQUIRE_AUTH" >/dev/null; then
  pass "require-auth.ts enforces admin/auditor roles"
else
  fail "require-auth.ts enforces admin/auditor roles"
fi
check_contains "$REQUIRE_AUTH" 'status: "APPROVED"' "require-auth.ts enforces approved KYC for LIVE mode"

check_contains "$LEGACY_AUTH" "export const requireAdminMfa = requireAdminRecentMfa();" "legacy middleware exposes requireAdminMfa"
check_contains "$LEGACY_AUTH" "export const requireMfa = requireRecentMfa();" "legacy middleware maps requireMfa to recent-MFA gate"

echo
echo "All Pass 1.5C static checks passed."
