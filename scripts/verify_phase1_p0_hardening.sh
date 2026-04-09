#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

fail=0

check_absent() {
  local pattern="$1"
  local description="$2"
  if grep -RIn --exclude='*.bak.*' --exclude='verify_phase1_p0_hardening.sh' --exclude='apply_phase1_p0_hardening.sh' "$pattern" docker-compose*.yml apps/api/src 2>/dev/null; then
    echo "[FAIL] $description"
    fail=1
  else
    echo "[PASS] $description"
  fi
}

check_present() {
  local pattern="$1"
  local file="$2"
  local description="$3"
  if grep -n "$pattern" "$file" >/dev/null 2>&1; then
    echo "[PASS] $description"
  else
    echo "[FAIL] $description"
    fail=1
  fi
}

check_absent 'ENABLE_BOT_FARM' 'Bot farm toggle removed from compose files'
check_absent 'dev_secret_change_me' 'JWT fallback secret removed'
check_absent 'x-user' 'Legacy x-user header auth removed'
check_absent 'x-mfa' 'Legacy x-mfa header bypass removed'
check_absent 'dev-only-change-me' 'Dangerous OTP fallback removed'

check_present 'simpleRateLimit' 'apps/api/src/modules/auth/auth.routes.ts' 'Auth routes have rate limiting'
check_present 'simpleRateLimit' 'apps/api/src/modules/verification/verification.routes.ts' 'Verification routes have rate limiting'
check_present 'server.close' 'apps/api/src/server.ts' 'Graceful shutdown added to server'
check_present 'OTP_HMAC_SECRET' 'apps/api/src/modules/notifications/notifications.config.ts' 'Notification config requires OTP secret'
check_present 'prisma.session.updateMany' 'apps/api/src/modules/verification/verification.service.ts' 'Password reset revokes active sessions'

if [[ $fail -ne 0 ]]; then
  echo
  echo "Verification failed. Review the failing checks above."
  exit 1
fi

echo
echo "All static checks passed."
