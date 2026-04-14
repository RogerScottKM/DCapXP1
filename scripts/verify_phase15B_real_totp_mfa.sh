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

check_not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq "$pattern" "$file"; then
    fail "$label"
  else
    pass "$label"
  fi
}

check_contains "$ROOT/apps/api/prisma/schema.prisma" 'mfaMethod String?' 'schema.prisma adds Session.mfaMethod'
check_contains "$ROOT/apps/api/prisma/schema.prisma" 'mfaVerifiedAt DateTime?' 'schema.prisma adds Session.mfaVerifiedAt'
check_contains "$ROOT/apps/api/prisma/migrations/20260411213000_phase15b_session_mfa/migration.sql" 'ADD COLUMN IF NOT EXISTS "mfaMethod"' 'migration adds mfaMethod column'
check_contains "$ROOT/apps/api/prisma/migrations/20260411213000_phase15b_session_mfa/migration.sql" 'ADD COLUMN IF NOT EXISTS "mfaVerifiedAt"' 'migration adds mfaVerifiedAt column'

check_contains "$ROOT/apps/api/src/modules/auth/mfa.service.ts" 'authenticator.generateSecret' 'mfa.service generates TOTP secrets'
check_contains "$ROOT/apps/api/src/modules/auth/mfa.service.ts" 'authenticator.keyuri' 'mfa.service builds otpauth URL'
check_contains "$ROOT/apps/api/src/modules/auth/mfa.service.ts" 'aes-256-gcm' 'mfa.service encrypts TOTP secrets'
check_contains "$ROOT/apps/api/src/modules/auth/mfa.service.ts" 'verifyTotpChallenge' 'mfa.service verifies TOTP challenge'
check_contains "$ROOT/apps/api/src/modules/auth/mfa.service.ts" 'mfaVerifiedAt' 'mfa.service updates session MFA timestamp'

check_contains "$ROOT/apps/api/src/modules/auth/auth.controller.ts" 'beginTotpEnrollment' 'auth.controller exports beginTotpEnrollment'
check_contains "$ROOT/apps/api/src/modules/auth/auth.controller.ts" 'confirmTotpEnrollment' 'auth.controller exports confirmTotpEnrollment'
check_contains "$ROOT/apps/api/src/modules/auth/auth.controller.ts" 'beginTotpChallenge' 'auth.controller exports beginTotpChallenge'
check_contains "$ROOT/apps/api/src/modules/auth/auth.controller.ts" 'confirmTotpChallenge' 'auth.controller exports confirmTotpChallenge'

check_contains "$ROOT/apps/api/src/modules/auth/auth.routes.ts" '/auth/mfa/totp/enroll' 'auth.routes includes TOTP enroll route'
check_contains "$ROOT/apps/api/src/modules/auth/auth.routes.ts" '/auth/mfa/totp/enroll/verify' 'auth.routes includes TOTP enroll verify route'
check_contains "$ROOT/apps/api/src/modules/auth/auth.routes.ts" '/auth/mfa/totp/challenge' 'auth.routes includes TOTP challenge route'
check_contains "$ROOT/apps/api/src/modules/auth/auth.routes.ts" '/auth/mfa/totp/challenge/verify' 'auth.routes includes TOTP challenge verify route'

check_contains "$ROOT/apps/api/src/middleware/require-auth.ts" 'mfaVerifiedAt?: Date | null;' 'require-auth.ts extends auth context with mfaVerifiedAt'
check_contains "$ROOT/apps/api/src/middleware/require-auth.ts" 'requireRecentMfa' 'require-auth.ts exports requireRecentMfa'
check_contains "$ROOT/apps/api/src/middleware/require-auth.ts" 'MFA_REQUIRED' 'require-auth.ts returns MFA_REQUIRED when missing'
check_contains "$ROOT/apps/api/src/middleware/require-auth.ts" 'MFA_EXPIRED' 'require-auth.ts returns MFA_EXPIRED when stale'

check_contains "$ROOT/apps/api/src/middleware/auth.ts" 'requireRecentMfa' 'middleware/auth.ts maps legacy requireMfa to requireRecentMfa'

check_contains "$ROOT/.env.example" 'MFA_TOTP_ISSUER=' '.env.example includes MFA_TOTP_ISSUER'
check_contains "$ROOT/.env.example" 'MFA_TOTP_ENCRYPTION_KEY=' '.env.example includes MFA_TOTP_ENCRYPTION_KEY'
check_contains "$ROOT/docker-compose.yml" 'MFA_TOTP_ISSUER:' 'docker-compose.yml passes MFA_TOTP_ISSUER'
check_contains "$ROOT/docker-compose.yml" 'MFA_TOTP_ENCRYPTION_KEY:' 'docker-compose.yml passes MFA_TOTP_ENCRYPTION_KEY'
check_contains "$ROOT/docker-compose.prod.yml" 'MFA_TOTP_ISSUER:' 'docker-compose.prod.yml passes MFA_TOTP_ISSUER'
check_contains "$ROOT/docker-compose.prod.yml" 'MFA_TOTP_ENCRYPTION_KEY:' 'docker-compose.prod.yml passes MFA_TOTP_ENCRYPTION_KEY'

check_not_contains "$ROOT/apps/api/src/middleware/auth.ts" 'MFA_NOT_IMPLEMENTED' 'legacy MFA placeholder removed'

echo
echo 'All Pass B static checks passed.'
