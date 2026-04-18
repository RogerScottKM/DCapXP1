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

COMPOSE="$ROOT/docker-compose.yml"
CONFIG="$ROOT/infra/vault/config/vault.hcl"
README="$ROOT/infra/vault/README.md"

[ -f "$COMPOSE" ] || fail "docker-compose.yml exists"
[ -f "$CONFIG" ] || fail "vault.hcl exists"
[ -f "$README" ] || fail "Vault README exists"

contains "$COMPOSE" 'vault:' "docker-compose defines vault service"
contains "$COMPOSE" 'hashicorp/vault:1.19' "vault service uses Vault image"
contains "$COMPOSE" '127.0.0.1:8200:8200' "vault service exposes local port 8200"
contains "$COMPOSE" './infra/vault/config:/vault/config:ro' "vault service mounts config read-only"
contains "$COMPOSE" 'dcapx_vault:/vault/data' "vault service mounts persistent raft data"
contains "$COMPOSE" 'dcapx_vault_file:/vault/file' "vault service mounts persistent file storage"
contains "$COMPOSE" 'dcapx_vault:' "docker-compose defines dcapx_vault volume"
contains "$COMPOSE" 'dcapx_vault_file:' "docker-compose defines dcapx_vault_file volume"

contains "$CONFIG" 'storage "raft"' "vault config uses raft storage"
contains "$CONFIG" 'path    = "/vault/data"' "vault config stores raft data persistently"
contains "$CONFIG" 'listener "tcp"' "vault config defines tcp listener"
contains "$CONFIG" 'tls_disable     = 1' "vault config disables TLS for local bootstrap"
contains "$CONFIG" 'api_addr     = "http://vault:8200"' "vault config sets container API address"

echo "[INFO] Running docker compose config"
(cd "$ROOT" && docker compose config >/tmp/dcapx-vault-compose.out) || fail "docker compose config passes"
pass "docker compose config passes"

echo "[INFO] Starting vault service"
(cd "$ROOT" && docker compose up -d vault >/tmp/dcapx-vault-up.out 2>&1) || fail "docker compose up -d vault"

sleep 3

(cd "$ROOT" && docker compose ps vault | grep -q "vault") || fail "vault container is running"
pass "vault container is running"

HTTP_CODE="$(curl -s -o /tmp/dcapx-vault-health.out -w "%{http_code}" http://127.0.0.1:8200/v1/sys/health || true)"
case "$HTTP_CODE" in
  200|429|472|473|501|503)
    pass "vault HTTP health endpoint is reachable (status $HTTP_CODE)"
    ;;
  *)
    echo "[INFO] Unexpected Vault health response code: $HTTP_CODE"
    [ -f /tmp/dcapx-vault-health.out ] && cat /tmp/dcapx-vault-health.out
    fail "vault HTTP health endpoint is reachable"
    ;;
esac

echo
echo "Resolved repo root: $ROOT"
echo "All Phase Vault-1 service stand-up checks passed."
