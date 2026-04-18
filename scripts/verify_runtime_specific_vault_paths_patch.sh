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
HOST_ENV="$ROOT/.env.vault.host.example"
SCRIPT="$ROOT/apps/api/src/scripts/print-vault-context.ts"
TEST="$ROOT/apps/api/test/vault-context.script.test.ts"
COMPOSE="$ROOT/docker-compose.yml"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$HOST_ENV" ] || fail ".env.vault.host.example exists"
[ -f "$SCRIPT" ] || fail "print-vault-context.ts exists"
[ -f "$TEST" ] || fail "vault-context.script.test.ts exists"
[ -f "$COMPOSE" ] || fail "docker-compose.yml exists"

contains "$PKG" '"vault:verify": "pnpm build && node dist/scripts/print-vault-context.js"' "package.json includes vault:verify script"
contains "$PKG" '"test:vault-context": "vitest run test/vault-context.script.test.ts"' "package.json includes focused vault-context test script"

contains "$HOST_ENV" 'VAULT_SECRET_PATH=secret/data/dcapx/api-host' "host env example uses api-host secret path"
contains "$HOST_ENV" 'VAULT_OVERRIDE_ENV=true' "host env example enables vault override"
contains "$HOST_ENV" 'VAULT_SECRET_ID_FILE=/absolute/path/to/host-cli.secret-id' "host env example documents host secret id file"
contains "$HOST_ENV" '# Keep the final DATABASE_URL inside Vault' "host env example keeps DATABASE_URL out of file"

contains "$SCRIPT" 'export function maskDatabaseUrl' "vault-context script exports DB URL masker"
contains "$SCRIPT" 'export async function collectVaultContext' "vault-context script exports context collector"
contains "$SCRIPT" 'await bootstrapSecrets();' "vault-context script bootstraps secrets before inspection"
contains "$SCRIPT" 'databaseUrlMasked: maskDatabaseUrl(env.DATABASE_URL)' "vault-context script prints masked DATABASE_URL only"

contains "$TEST" 'masks database URLs without exposing passwords' "vault-context tests cover masking"
contains "$TEST" 'collects a masked runtime-specific vault context after bootstrap' "vault-context tests cover masked runtime context"

contains "$COMPOSE" 'VAULT_ENABLED: ${VAULT_ENABLED_API_CONTAINER:-false}' "docker-compose uses runtime-specific VAULT_ENABLED_API_CONTAINER"
contains "$COMPOSE" 'VAULT_ADDR: ${VAULT_ADDR_API_CONTAINER:-}' "docker-compose uses runtime-specific VAULT_ADDR_API_CONTAINER"
contains "$COMPOSE" 'VAULT_MOUNT_PATH: ${VAULT_MOUNT_PATH_API_CONTAINER:-approle}' "docker-compose uses runtime-specific VAULT_MOUNT_PATH_API_CONTAINER"
contains "$COMPOSE" 'VAULT_ROLE_ID: ${VAULT_ROLE_ID_API_CONTAINER:-}' "docker-compose uses runtime-specific VAULT_ROLE_ID_API_CONTAINER"
contains "$COMPOSE" 'VAULT_SECRET_ID: ${VAULT_SECRET_ID_API_CONTAINER:-}' "docker-compose uses runtime-specific VAULT_SECRET_ID_API_CONTAINER"
contains "$COMPOSE" 'VAULT_SECRET_ID_FILE: ${VAULT_SECRET_ID_FILE_API_CONTAINER:-}' "docker-compose uses runtime-specific VAULT_SECRET_ID_FILE_API_CONTAINER"
contains "$COMPOSE" 'VAULT_SECRET_PATH: ${VAULT_SECRET_PATH_API_CONTAINER:-secret/data/dcapx/api-container}' "docker-compose uses runtime-specific api-container secret path"
contains "$COMPOSE" 'VAULT_OVERRIDE_ENV: ${VAULT_OVERRIDE_ENV_API_CONTAINER:-true}' "docker-compose enables runtime-specific Vault override"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused vault-context tests"
if (cd "$ROOT" && pnpm --filter api test:vault-context); then
  pass "focused vault-context tests pass"
else
  fail "focused vault-context tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All runtime-specific Vault path checks passed."
