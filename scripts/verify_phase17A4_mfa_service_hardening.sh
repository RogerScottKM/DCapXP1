#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
SRC="$ROOT/apps/api/src/modules/auth/mfa.service.ts"
TEST="$ROOT/apps/api/test/mfa.service.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SRC" ] || fail "mfa.service.ts exists"
[ -f "$TEST" ] || fail "mfa.service.test.ts exists"

contains "$PKG" '"test:auth:mfa-service"' "package.json includes mfa-service test script"
contains "$PKG" 'vitest run test/mfa.service.test.ts' "package.json mfa-service script points at focused test file"

contains "$SRC" 'private encryptSecret(secret: string): string' "mfa service exposes secret encryption helper"
contains "$SRC" 'private decryptSecret(secretEncrypted: string): string' "mfa service exposes secret decryption helper"
contains "$SRC" 'private deriveKey(): Buffer' "mfa service derives an encryption key"
contains "$SRC" 'private generateRecoveryCode(): string' "mfa service generates formatted recovery codes"
contains "$SRC" 'while (raw.length < 12)' "mfa service guarantees enough recovery-code characters before formatting"
contains "$SRC" 'private hashRecoveryCode(code: string): string' "mfa service hashes normalized recovery codes"
contains "$SRC" 'secretEncrypted = this.encryptSecret(secret)' "mfa enrollment stores encrypted TOTP secrets"
contains "$SRC" 'const secret = this.decryptSecret(factor.secretEncrypted);' "mfa service uses decryptSecret during verification flows"
contains "$SRC" 'mfaMethod: "TOTP"' "mfa challenge stamps TOTP on the session"
contains "$SRC" 'mfaVerifiedAt: now' "mfa challenge stamps verification time on the session"
contains "$SRC" 'id: { not: sessionId }' "mfa service revokes other sessions while excluding the current session"
contains "$SRC" 'code.replace(/[^A-Za-z0-9]/g, "").toUpperCase()' "mfa recovery code hashing normalizes user input"

contains "$TEST" 'vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }))' "test file mocks security audit persistence"
contains "$TEST" 'encrypts and decrypts a TOTP secret round-trip' "test file covers crypto round-trip"
contains "$TEST" 'rejects malformed encrypted TOTP secrets' "test file covers malformed stored secret rejection"
contains "$TEST" 'rejects missing MFA_TOTP_ENCRYPTION_KEY' "test file covers missing encryption-key rejection"
contains "$TEST" 'activates enrollment with a valid token using the real encrypted secret path' "test file covers real encrypted activation path"
contains "$TEST" 'clears MFA on other sessions but preserves the current session during activation' "test file covers session revocation semantics during activation"
contains "$TEST" 'stamps the session on a valid TOTP challenge using the real encrypted secret path' "test file covers real encrypted challenge path"
contains "$TEST" 'regenerateRecoveryCodes generates codes and revokes other sessions' "test file covers recovery code generation and revocation semantics"
contains "$TEST" 'regenerateRecoveryCodes clamps requested counts to the supported range' "test file covers recovery code count clamping"
contains "$TEST" 'normalizes recovery-code input before lookup and stamps the session' "test file covers normalized recovery-code lookup"
contains "$TEST" 'expectApiError(' "test file uses compatible sync ApiError assertions"

echo

echo "Resolved repo root: $ROOT"
echo "All Phase 17 A4 static checks passed."
