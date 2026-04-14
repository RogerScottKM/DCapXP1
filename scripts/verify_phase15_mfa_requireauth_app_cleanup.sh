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

PACKAGE_JSON="$ROOT/apps/api/package.json"
REQUIRE_AUTH_TS="$ROOT/apps/api/src/middleware/require-auth.ts"
AUTH_ROUTES_TS="$ROOT/apps/api/src/modules/auth/auth.routes.ts"
AUTH_CONTROLLER_TS="$ROOT/apps/api/src/modules/auth/auth.controller.ts"
MFA_SERVICE_TS="$ROOT/apps/api/src/modules/auth/mfa.service.ts"
APP_TS="$ROOT/apps/api/src/app.ts"
SCHEMA="$ROOT/apps/api/prisma/schema.prisma"
ENV_EXAMPLE="$ROOT/.env.example"
COMPOSE_YML="$ROOT/docker-compose.yml"
COMPOSE_PROD_YML="$ROOT/docker-compose.prod.yml"
MIGRATION_SQL="$ROOT/apps/api/prisma/migrations/20260411010000_phase15_mfa_session_stepup/migration.sql"

check_contains "$PACKAGE_JSON" '"helmet"' "package.json includes helmet dependency"
check_contains "$PACKAGE_JSON" '"otplib"' "package.json includes otplib dependency"

check_contains "$REQUIRE_AUTH_TS" 'export function requireRole' "require-auth exports requireRole"
check_contains "$REQUIRE_AUTH_TS" 'export function requireRecentMfa' "require-auth exports requireRecentMfa"
check_contains "$REQUIRE_AUTH_TS" 'export function requireLiveModeEligible' "require-auth exports requireLiveModeEligible"
check_contains "$REQUIRE_AUTH_TS" 'mfaVerifiedAt' "require-auth enriches request auth with mfaVerifiedAt"
check_contains "$REQUIRE_AUTH_TS" 'roles:' "require-auth enriches request auth with roles"

check_contains "$AUTH_ROUTES_TS" '/auth/mfa/totp/setup' "auth routes include TOTP setup"
check_contains "$AUTH_ROUTES_TS" '/auth/mfa/totp/verify' "auth routes include TOTP verify"
check_contains "$AUTH_ROUTES_TS" '/auth/mfa/totp/challenge' "auth routes include TOTP challenge"
check_contains "$AUTH_ROUTES_TS" 'mfaLimiter' "auth routes include MFA rate limiter"

check_contains "$AUTH_CONTROLLER_TS" 'beginTotpEnrollment' "auth controller wires TOTP setup"
check_contains "$AUTH_CONTROLLER_TS" 'verifyTotpEnrollment' "auth controller wires TOTP verify"
check_contains "$AUTH_CONTROLLER_TS" 'challengeTotp' "auth controller wires TOTP challenge"

check_contains "$MFA_SERVICE_TS" 'authenticator.generateSecret' "mfa.service generates TOTP secret"
check_contains "$MFA_SERVICE_TS" 'authenticator.keyuri' "mfa.service creates otpauth URL"
check_contains "$MFA_SERVICE_TS" 'mfaVerifiedAt' "mfa.service updates session MFA timestamp"
check_contains "$MFA_SERVICE_TS" 'MFA_TOTP_ENCRYPTION_KEY' "mfa.service requires encryption key"

check_contains "$APP_TS" 'helmet(' "app.ts enables helmet"
check_contains "$APP_TS" 'app.disable("x-powered-by")' "app.ts disables x-powered-by"
check_contains "$APP_TS" 'Route not found.' "app.ts returns JSON 404"
check_contains "$APP_TS" '/backend-api/v1/market' "app.ts mounts backend-api market prefix"
check_contains "$APP_TS" '/backend-api/v1/stream' "app.ts mounts backend-api stream prefix"

check_contains "$SCHEMA" 'mfaVerifiedAt    DateTime?' "schema adds Session.mfaVerifiedAt"
check_contains "$SCHEMA" 'mfaMethod        String?' "schema adds Session.mfaMethod"
check_contains "$MIGRATION_SQL" 'ADD COLUMN IF NOT EXISTS "mfaVerifiedAt"' "migration adds Session.mfaVerifiedAt"
check_contains "$MIGRATION_SQL" 'ADD COLUMN IF NOT EXISTS "mfaMethod"' "migration adds Session.mfaMethod"

check_contains "$ENV_EXAMPLE" 'MFA_TOTP_ISSUER=' ".env.example includes MFA_TOTP_ISSUER"
check_contains "$ENV_EXAMPLE" 'MFA_TOTP_ENCRYPTION_KEY=' ".env.example includes MFA_TOTP_ENCRYPTION_KEY"
check_contains "$COMPOSE_YML" 'MFA_TOTP_ISSUER:' "docker-compose.yml passes MFA_TOTP_ISSUER"
check_contains "$COMPOSE_YML" 'MFA_TOTP_ENCRYPTION_KEY:' "docker-compose.yml passes MFA_TOTP_ENCRYPTION_KEY"
check_contains "$COMPOSE_PROD_YML" 'MFA_TOTP_ISSUER:' "docker-compose.prod.yml passes MFA_TOTP_ISSUER"
check_contains "$COMPOSE_PROD_YML" 'MFA_TOTP_ENCRYPTION_KEY:' "docker-compose.prod.yml passes MFA_TOTP_ENCRYPTION_KEY"

echo
echo "All static MFA + require-auth + app cleanup checks passed."
EOF_TS
