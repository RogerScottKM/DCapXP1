#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

pass(){ echo "[PASS] $1"; }
fail(){ echo "[FAIL] $1"; exit 1; }
check_contains(){ local f="$1" p="$2" l="$3"; grep -Fq "$p" "$f" && pass "$l" || fail "$l"; }

SCHEMA="$ROOT/apps/api/prisma/schema.prisma"
MIGRATION="$ROOT/apps/api/prisma/migrations/20260410_phase15b_session_mfa/migration.sql"
REQAUTH="$ROOT/apps/api/src/middleware/require-auth.ts"
LEGACYAUTH="$ROOT/apps/api/src/middleware/auth.ts"
ROUTES="$ROOT/apps/api/src/modules/auth/auth.routes.ts"
CONTROLLER="$ROOT/apps/api/src/modules/auth/auth.controller.ts"
MFASVC="$ROOT/apps/api/src/modules/auth/mfa.service.ts"
AUTHSVC="$ROOT/apps/api/src/modules/auth/auth.service.ts"
ENVEX="$ROOT/.env.example"
COMPOSE="$ROOT/docker-compose.yml"
COMPOSE_PROD="$ROOT/docker-compose.prod.yml"

check_contains "$SCHEMA" 'mfaMethod' 'schema.prisma adds Session.mfaMethod'
check_contains "$SCHEMA" 'mfaVerifiedAt' 'schema.prisma adds Session.mfaVerifiedAt'
check_contains "$MIGRATION" 'mfaMethod' 'migration adds mfaMethod column'
check_contains "$MIGRATION" 'mfaVerifiedAt' 'migration adds mfaVerifiedAt column'

check_contains "$MFASVC" 'beginTotpEnrollment' 'mfa.service.ts defines TOTP enrollment'
check_contains "$MFASVC" 'activateTotpEnrollment' 'mfa.service.ts defines TOTP activation'
check_contains "$MFASVC" 'challengeTotp' 'mfa.service.ts defines TOTP challenge'
check_contains "$MFASVC" 'authenticator.generateSecret' 'mfa.service.ts generates TOTP secrets'
check_contains "$MFASVC" 'createCipheriv' 'mfa.service.ts encrypts TOTP secrets'

check_contains "$CONTROLLER" 'enrollTotp' 'auth.controller.ts exports enrollTotp'
check_contains "$CONTROLLER" 'activateTotp' 'auth.controller.ts exports activateTotp'
check_contains "$CONTROLLER" 'challengeTotp' 'auth.controller.ts exports challengeTotp'

check_contains "$ROUTES" '/auth/mfa/totp/enroll' 'auth.routes.ts mounts TOTP enroll route'
check_contains "$ROUTES" '/auth/mfa/totp/activate' 'auth.routes.ts mounts TOTP activate route'
check_contains "$ROUTES" '/auth/mfa/totp/challenge' 'auth.routes.ts mounts TOTP challenge route'

check_contains "$REQAUTH" 'requireRecentMfa' 'require-auth.ts exports requireRecentMfa'
check_contains "$REQAUTH" 'mfaVerifiedAt' 'require-auth.ts tracks mfaVerifiedAt'
check_contains "$REQAUTH" 'MFA_REQUIRED' 'require-auth.ts enforces recent MFA'

check_contains "$LEGACYAUTH" 'requireRecentMfa()' 'legacy middleware requireMfa maps to real recent-MFA gate'

check_contains "$AUTHSVC" 'mfaMethod: session.mfaMethod ?? null' 'auth.service.ts returns session mfaMethod'
check_contains "$AUTHSVC" 'mfaVerifiedAt: session.mfaVerifiedAt ?? null' 'auth.service.ts returns session mfaVerifiedAt'

check_contains "$ENVEX" 'MFA_TOTP_ISSUER=' '.env.example includes MFA_TOTP_ISSUER'
check_contains "$ENVEX" 'MFA_TOTP_ENCRYPTION_KEY=' '.env.example includes MFA_TOTP_ENCRYPTION_KEY'
check_contains "$COMPOSE" 'MFA_TOTP_ISSUER:' 'docker-compose.yml passes MFA_TOTP_ISSUER'
check_contains "$COMPOSE" 'MFA_TOTP_ENCRYPTION_KEY:' 'docker-compose.yml passes MFA_TOTP_ENCRYPTION_KEY'
check_contains "$COMPOSE_PROD" 'MFA_TOTP_ISSUER:' 'docker-compose.prod.yml passes MFA_TOTP_ISSUER'
check_contains "$COMPOSE_PROD" 'MFA_TOTP_ENCRYPTION_KEY:' 'docker-compose.prod.yml passes MFA_TOTP_ENCRYPTION_KEY'

echo
echo "All Pass B2 static checks passed."
