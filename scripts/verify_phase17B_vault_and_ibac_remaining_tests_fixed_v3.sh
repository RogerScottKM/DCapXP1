#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
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
VAULT_SRC="$ROOT/apps/api/src/lib/vault-client.ts"
BOOTSTRAP_SRC="$ROOT/apps/api/src/lib/bootstrap-secrets.ts"
IBAC_SRC="$ROOT/apps/api/src/middleware/ibac.ts"
VAULT_TEST="$ROOT/apps/api/test/vault-bootstrap.test.ts"
IBAC_TEST="$ROOT/apps/api/test/ibac.middleware.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$VAULT_SRC" ] || fail "vault-client source exists"
[ -f "$BOOTSTRAP_SRC" ] || fail "bootstrap-secrets source exists"
[ -f "$IBAC_SRC" ] || fail "ibac middleware source exists"
[ -f "$VAULT_TEST" ] || fail "vault-bootstrap test exists"
[ -f "$IBAC_TEST" ] || fail "ibac middleware test exists"

contains "$PKG" '"test:auth:vault-bootstrap"' "package.json includes vault-bootstrap test script"
contains "$PKG" '"test:middleware:ibac"' "package.json includes ibac middleware test script"
contains "$PKG" '"test:pass-b"' "package.json includes combined Pass B test script"
contains "$PKG" 'vitest run test/vault-bootstrap.test.ts' "vault-bootstrap script points at focused vault test"
contains "$PKG" 'vitest run test/ibac.middleware.test.ts' "ibac script points at focused middleware test"
contains "$PKG" 'vitest run test/vault-bootstrap.test.ts test/ibac.middleware.test.ts' "combined Pass B script runs both focused suites"

contains "$VAULT_SRC" 'auth/${config.mountPath}/login' "vault client uses AppRole login path"
contains "$VAULT_SRC" 'tokenRevokeSelf' "vault client revokes the Vault token in a finally block"
contains "$VAULT_SRC" 'VAULT_SECRET_ID_FILE' "vault client supports secret-id file loading"
contains "$BOOTSTRAP_SRC" 'RESERVED_KEYS' "bootstrap secrets protects reserved VAULT_* keys"
contains "$BOOTSTRAP_SRC" 'VAULT_OVERRIDE_ENV' "bootstrap secrets supports override mode"

contains "$IBAC_SRC" 'x-agent-id' "ibac middleware reads x-agent-id"
contains "$IBAC_SRC" 'x-agent-ts' "ibac middleware reads x-agent-ts"
contains "$IBAC_SRC" 'x-agent-nonce' "ibac middleware reads x-agent-nonce"
contains "$IBAC_SRC" 'x-agent-sig' "ibac middleware reads x-agent-sig"
contains "$IBAC_SRC" 'STALE_TIMESTAMP' "ibac middleware rejects stale timestamps"
contains "$IBAC_SRC" 'REPLAY_NONCE' "ibac middleware rejects replayed nonces"
contains "$IBAC_SRC" 'canonicalStringify' "ibac middleware canonicalizes the request body for signing"
contains "$IBAC_SRC" 'crypto.verify' "ibac middleware verifies Ed25519 signatures"
contains "$IBAC_SRC" 'req.principal =' "ibac middleware attaches principal context"
contains "$IBAC_SRC" 'mandateUsage.upsert' "ibac helpers bump daily usage via upsert"

contains "$VAULT_TEST" 'loads the secret id from VAULT_SECRET_ID_FILE' "vault test covers secret-id file loading"
contains "$VAULT_TEST" 'fetches kv-v2 secrets and revokes the token afterward' "vault test covers kv-v2 fetch and token revoke"
contains "$VAULT_TEST" 'revokes the token even when the vault read fails' "vault test covers revoke-on-failure"
contains "$VAULT_TEST" 'skips reserved VAULT_* keys and preserves existing values when override is disabled' "vault test covers reserved-key and no-override behavior"
contains "$VAULT_TEST" 'overrides existing values when VAULT_OVERRIDE_ENV is enabled' "vault test covers override mode"

contains "$IBAC_TEST" 'rejects requests with missing agent authentication headers' "ibac test covers missing headers"
contains "$IBAC_TEST" 'rejects stale timestamps' "ibac test covers stale timestamp"
contains "$IBAC_TEST" 'rejects replayed nonces' "ibac test covers replay nonce"
contains "$IBAC_TEST" 'rejects invalid agent signatures' "ibac test covers signature rejection"
contains "$IBAC_TEST" 'attaches agent principal context on a valid signed request' "ibac test covers valid principal attachment"
contains "$IBAC_TEST" 'bumps order counts and notional usage using the UTC day bucket' "ibac test covers usage bump helpers"

echo
echo "Resolved repo root: $ROOT"
echo "All Pass B static checks passed."
