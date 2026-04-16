#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
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
AUTH="$ROOT/apps/api/src/modules/auth/auth.service.ts"
TEST="$ROOT/apps/api/test/session.resolution.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$AUTH" ] || fail "auth.service.ts exists"
[ -f "$TEST" ] || fail "session.resolution.test.ts exists"

contains "$PKG" '"test:auth:session-resolution"' "package.json includes session resolution test script"
contains "$PKG" 'vitest run test/session.resolution.test.ts' "package.json session resolution script points at the focused test file"

contains "$AUTH" 'if (!session.user) return null;' "auth service guards missing session user relation"
contains "$AUTH" 'let secretOk = false;' "auth service initializes guarded secret verification result"
contains "$AUTH" 'secretOk = await verifySessionSecret(session.refreshTokenHash, parsed.secret);' "auth service still verifies session secret"
contains "$AUTH" 'catch {' "auth service catches session secret verification failures"
contains "$AUTH" 'if (!secretOk) return null;' "auth service returns null on invalid auth states"

contains "$TEST" 'vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }))' "test file mocks security audit persistence"
contains "$TEST" 'returns null when the session cookie cannot be parsed' "test file covers malformed cookie parse"
contains "$TEST" 'returns null when session user relation is missing' "test file covers missing user relation"
contains "$TEST" 'returns null when session secret verification throws' "test file covers verifier exception path"
contains "$TEST" 'returns auth context with MFA fields for a valid session' "test file covers valid auth resolution"
contains "$TEST" 'revokes the parsed session id and clears the cookie' "test file covers logout revocation path"
contains "$TEST" 'clears the cookie and returns ok when no session cookie is present' "test file covers logout with no cookie"
contains "$TEST" 'clears the cookie and remains idempotent when no active session matches' "test file covers idempotent logout path"

printf '\nResolved repo root: %s\n' "$ROOT"
echo "All Phase 17 A2 static checks passed."
