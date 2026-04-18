#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

BOOTSTRAP_DIR="${HOME}/.dcapx-vault"
INIT_FILE="${BOOTSTRAP_DIR}/init.json"
HOST_SECRET_FILE="${BOOTSTRAP_DIR}/host-cli.secret-id"
CONTAINER_SECRET_FILE="${BOOTSTRAP_DIR}/api-container.secret-id"
HOST_ENV_FILE="${ROOT}/.env.vault.host"
CONTAINER_ENV_FILE="${ROOT}/.env.vault.container"
COMPOSE_FILE="${ROOT}/docker-compose.yml"
GITIGNORE_FILE="${ROOT}/.gitignore"

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

[ -f "$INIT_FILE" ] || fail "init.json exists under ${BOOTSTRAP_DIR}"
[ -f "$HOST_SECRET_FILE" ] || fail "host secret-id file exists"
[ -f "$CONTAINER_SECRET_FILE" ] || fail "container secret-id file exists"
[ -f "$HOST_ENV_FILE" ] || fail ".env.vault.host exists"
[ -f "$CONTAINER_ENV_FILE" ] || fail ".env.vault.container exists"
[ -f "$COMPOSE_FILE" ] || fail "docker-compose.yml exists"
[ -f "$GITIGNORE_FILE" ] || fail ".gitignore exists"

[[ "$(stat -c '%a' "$HOST_SECRET_FILE")" == "600" ]] && pass "host secret-id permissions are 600" || fail "host secret-id permissions are 600"
[[ "$(stat -c '%a' "$CONTAINER_SECRET_FILE")" == "600" ]] && pass "container secret-id permissions are 600" || fail "container secret-id permissions are 600"
[[ "$(stat -c '%a' "$INIT_FILE")" == "600" ]] && pass "init.json permissions are 600" || fail "init.json permissions are 600"

contains "$HOST_ENV_FILE" 'VAULT_ENABLED=true' "host env enables Vault"
contains "$HOST_ENV_FILE" 'VAULT_SECRET_PATH=secret/data/dcapx/api-host' "host env uses api-host path"
contains "$CONTAINER_ENV_FILE" 'VAULT_ENABLED=true' "container env enables Vault"
contains "$CONTAINER_ENV_FILE" 'VAULT_SECRET_PATH=secret/data/dcapx/api-container' "container env uses api-container path"

contains "$COMPOSE_FILE" 'VAULT_BOOTSTRAP_FILE: /run/secrets/dcapx-api-container.env' "docker-compose api uses VAULT_BOOTSTRAP_FILE"
contains "$COMPOSE_FILE" './.env.vault.container:/run/secrets/dcapx-api-container.env:ro' "docker-compose api mounts container bootstrap file"
contains "$COMPOSE_FILE" '${HOME}/.dcapx-vault/api-container.secret-id:/run/secrets/dcapx-api-container.secret-id:ro' "docker-compose api mounts container secret-id file"

contains "$GITIGNORE_FILE" '.env.vault.host' ".gitignore excludes host vault bootstrap"
contains "$GITIGNORE_FILE" '.env.vault.container' ".gitignore excludes container vault bootstrap"

eval "$(
python3 - "${INIT_FILE}" <<'PY'
import json, shlex, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
print(f"ROOT_TOKEN={shlex.quote(data['root_token'])}")
PY
)"

vcli() {
  docker run --rm --network host     -e VAULT_ADDR="http://127.0.0.1:8200"     -e VAULT_TOKEN="${ROOT_TOKEN}"     hashicorp/vault:1.19 vault "$@"
}

echo "[INFO] Checking Vault-seeded host/container secrets"
vcli kv get -mount=secret -field=DATABASE_URL dcapx/api-host >/tmp/dcapx-host-dburl.out 2>/tmp/dcapx-host-dburl.err || { cat /tmp/dcapx-host-dburl.err || true; fail "Vault api-host secret exists"; }
pass "Vault api-host secret exists"

vcli kv get -mount=secret -field=DATABASE_URL dcapx/api-container >/tmp/dcapx-container-dburl.out 2>/tmp/dcapx-container-dburl.err || { cat /tmp/dcapx-container-dburl.err || true; fail "Vault api-container secret exists"; }
pass "Vault api-container secret exists"

echo "[INFO] Verifying host vault context"
(cd "$ROOT/apps/api" && pnpm vault:verify >/tmp/dcapx-host-vault-verify.out 2>/tmp/dcapx-host-vault-verify.err) || { cat /tmp/dcapx-host-vault-verify.err || true; fail "host pnpm vault:verify passes"; }
pass "host pnpm vault:verify passes"
contains /tmp/dcapx-host-vault-verify.out '"VAULT_ENABLED": "true"' "host vault:verify shows Vault enabled"
contains /tmp/dcapx-host-vault-verify.out '"VAULT_SECRET_PATH": "secret/data/dcapx/api-host"' "host vault:verify shows api-host path"
contains /tmp/dcapx-host-vault-verify.out '127.0.0.1:5445' "host vault:verify resolves host-safe DATABASE_URL"

echo "[INFO] Running host prisma migrate through Vault"
(cd "$ROOT/apps/api" && pnpm prisma:migrate:vault >/tmp/dcapx-host-migrate.out 2>/tmp/dcapx-host-migrate.err) || { cat /tmp/dcapx-host-migrate.err || true; fail "host pnpm prisma:migrate:vault passes"; }
pass "host pnpm prisma:migrate:vault passes"

echo "[INFO] Verifying container vault context"
(cd "$ROOT" && docker compose run --rm api sh -lc 'pnpm build >/dev/null && node dist/scripts/print-vault-context.js' >/tmp/dcapx-container-vault-verify.out 2>/tmp/dcapx-container-vault-verify.err) || { cat /tmp/dcapx-container-vault-verify.err || true; fail "container vault context check passes"; }
pass "container vault context check passes"
contains /tmp/dcapx-container-vault-verify.out '"VAULT_ENABLED": "true"' "container vault context shows Vault enabled"
contains /tmp/dcapx-container-vault-verify.out '"VAULT_SECRET_PATH": "secret/data/dcapx/api-container"' "container vault context shows api-container path"
contains /tmp/dcapx-container-vault-verify.out 'pg:5432' "container vault context resolves container-safe DATABASE_URL"

echo "[INFO] Restarting API against Vault"
(cd "$ROOT" && docker compose up -d --force-recreate api >/tmp/dcapx-api-restart.out 2>&1) || { cat /tmp/dcapx-api-restart.out || true; fail "docker compose api restart passes"; }
pass "docker compose api restart passes"

sleep 5
(cd "$ROOT" && docker compose logs api --tail=120 >/tmp/dcapx-api-vault-logs.out 2>&1) || fail "docker compose logs api available"
pass "docker compose logs api available"

if grep -Fq '[vault] bootstrap disabled' /tmp/dcapx-api-vault-logs.out; then
  fail "api logs no longer show vault bootstrap disabled"
else
  pass "api logs no longer show vault bootstrap disabled"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase Vault-2 init/seed checks passed."
