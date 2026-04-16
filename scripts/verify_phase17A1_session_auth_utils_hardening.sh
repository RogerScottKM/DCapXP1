#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

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
SRC="$ROOT/apps/api/src/lib/session-auth.ts"
TEST="$ROOT/apps/api/test/session-auth.utils.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SRC" ] || fail "session-auth.ts exists"
[ -f "$TEST" ] || fail "session-auth.utils.test.ts exists"

contains "$PKG" '"test:auth:session-utils"' "package.json includes session utils test script"
contains "$PKG" 'vitest run test/session-auth.utils.test.ts' "package.json session utils script points at the focused test file"

contains "$SRC" 'hashSessionSecret' "session-auth source exports hashSessionSecret"
contains "$SRC" 'verifySessionSecret' "session-auth source exports verifySessionSecret"
contains "$SRC" 'setSessionCookie' "session-auth source exports setSessionCookie"
contains "$SRC" 'clearSessionCookie' "session-auth source exports clearSessionCookie"

contains "$TEST" 'hashes and verifies a session secret round-trip' "test file covers hash/verify round-trip"
contains "$TEST" 'returns false for a wrong session secret' "test file covers wrong-secret verification"
contains "$TEST" 'preserves secret remainder after first dot' "test file locks current first-dot parser contract"
contains "$TEST" 'returns null when secret part is empty' "test file covers trailing-dot invalid cookie"
contains "$TEST" 'ignores partial-name cookie collisions' "test file covers exact cookie-name matching"
contains "$TEST" 'sets default HttpOnly Path SameSite and expiry attributes' "test file covers default cookie flags"
contains "$TEST" 'adds Secure in production and respects SESSION_COOKIE_SAMESITE' "test file covers production secure cookie flags"
contains "$TEST" 'clears the session cookie with immediate expiry' "test file covers cookie clearing semantics"

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 17 A1 static checks passed."
