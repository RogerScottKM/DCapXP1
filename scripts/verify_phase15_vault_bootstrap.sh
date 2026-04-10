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

line_number() {
  local file="$1"
  local pattern="$2"
  grep -nF "$pattern" "$file" | head -n1 | cut -d: -f1
}

PACKAGE_JSON="$ROOT/apps/api/package.json"
SERVER_TS="$ROOT/apps/api/src/server.ts"
VAULT_CLIENT_TS="$ROOT/apps/api/src/lib/vault-client.ts"
BOOTSTRAP_TS="$ROOT/apps/api/src/lib/bootstrap-secrets.ts"
ENV_EXAMPLE="$ROOT/.env.example"
COMPOSE_YML="$ROOT/docker-compose.yml"
COMPOSE_PROD_YML="$ROOT/docker-compose.prod.yml"

check_contains "$PACKAGE_JSON" '"node-vault"' "package.json includes node-vault dependency"

check_contains "$SERVER_TS" 'bootstrapSecrets' "server.ts calls bootstrapSecrets"

BOOTSTRAP_LINE="$(line_number "$SERVER_TS" 'await bootstrapSecrets();' || true)"
VALIDATE_LINE="$(line_number "$SERVER_TS" 'validateEnv();' || true)"
if [[ -n "${BOOTSTRAP_LINE}" && -n "${VALIDATE_LINE}" && "$BOOTSTRAP_LINE" -lt "$VALIDATE_LINE" ]]; then
  pass "server.ts awaits Vault bootstrap before validateEnv"
else
  fail "server.ts awaits Vault bootstrap before validateEnv"
fi

APP_IMPORT_LINE="$(line_number "$SERVER_TS" 'const appModule = await import("./app.js");' || true)"
PRISMA_IMPORT_LINE="$(line_number "$SERVER_TS" 'const prismaModule = await import("./lib/prisma.js");' || true)"

if [[ -n "${APP_IMPORT_LINE}" && -n "${BOOTSTRAP_LINE}" && "$APP_IMPORT_LINE" -gt "$BOOTSTRAP_LINE" ]]; then
  pass "server.ts lazy-loads app after bootstrap"
else
  fail "server.ts lazy-loads app after bootstrap"
fi

if [[ -n "${PRISMA_IMPORT_LINE}" && -n "${BOOTSTRAP_LINE}" && "$PRISMA_IMPORT_LINE" -gt "$BOOTSTRAP_LINE" ]]; then
  pass "server.ts lazy-loads prisma after bootstrap"
else
  fail "server.ts lazy-loads prisma after bootstrap"
fi

check_contains "$VAULT_CLIENT_TS" 'approle' "vault-client uses AppRole login path"
check_contains "$VAULT_CLIENT_TS" 'role_id' "vault-client submits role_id"
check_contains "$VAULT_CLIENT_TS" 'secret_id' "vault-client submits secret_id"
check_contains "$VAULT_CLIENT_TS" 'VAULT_SECRET_PATH' "vault-client reads Vault secret path"
check_contains "$VAULT_CLIENT_TS" 'VAULT_SECRET_ID_FILE' "vault-client prefers secret-id file support"

check_contains "$BOOTSTRAP_TS" 'vault-client' "bootstrap-secrets imports Vault fetcher"
check_contains "$BOOTSTRAP_TS" 'VAULT_OVERRIDE_ENV' "bootstrap-secrets supports override flag"

check_contains "$ENV_EXAMPLE" 'VAULT_ENABLED=' ".env.example includes VAULT_ENABLED"
check_contains "$ENV_EXAMPLE" 'VAULT_ADDR=' ".env.example includes VAULT_ADDR"
check_contains "$ENV_EXAMPLE" 'VAULT_ROLE_ID=' ".env.example includes VAULT_ROLE_ID"
check_contains "$ENV_EXAMPLE" 'VAULT_SECRET_ID_FILE=' ".env.example includes VAULT_SECRET_ID_FILE"
check_contains "$ENV_EXAMPLE" 'VAULT_SECRET_PATH=' ".env.example includes VAULT_SECRET_PATH"
check_contains "$ENV_EXAMPLE" 'VAULT_OVERRIDE_ENV=' ".env.example includes VAULT_OVERRIDE_ENV"
check_contains "$ENV_EXAMPLE" 'DATABASE_URL=' ".env.example still includes DATABASE_URL for Prisma prestart"

check_contains "$COMPOSE_YML" 'VAULT_ENABLED:' "docker-compose.yml passes VAULT_ENABLED to api"
check_contains "$COMPOSE_YML" 'VAULT_ROLE_ID:' "docker-compose.yml passes VAULT_ROLE_ID to api"
check_contains "$COMPOSE_YML" 'VAULT_SECRET_ID_FILE:' "docker-compose.yml passes VAULT_SECRET_ID_FILE to api"
check_contains "$COMPOSE_YML" 'RESEND_API_KEY:' "docker-compose.yml passes RESEND_API_KEY to api"

check_contains "$COMPOSE_PROD_YML" 'VAULT_ENABLED:' "docker-compose.prod.yml passes VAULT_ENABLED to api"
check_contains "$COMPOSE_PROD_YML" 'VAULT_ROLE_ID:' "docker-compose.prod.yml passes VAULT_ROLE_ID to api"
check_contains "$COMPOSE_PROD_YML" 'VAULT_SECRET_ID_FILE:' "docker-compose.prod.yml passes VAULT_SECRET_ID_FILE to api"
check_contains "$COMPOSE_PROD_YML" 'RESEND_API_KEY:' "docker-compose.prod.yml passes RESEND_API_KEY to api"

check_not_contains "$SERVER_TS" 'VAULT_TOKEN' "No legacy VAULT_TOKEN references found in patched files"
check_not_contains "$VAULT_CLIENT_TS" 'VAULT_TOKEN' "No legacy VAULT_TOKEN references found in patched files"

echo
echo "All static Vault bootstrap checks passed."
