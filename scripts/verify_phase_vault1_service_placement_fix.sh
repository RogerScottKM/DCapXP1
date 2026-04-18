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
[ -f "$COMPOSE" ] || fail "docker-compose.yml exists"

contains "$COMPOSE" 'services:' "compose has root services block"
contains "$COMPOSE" '  vault:' "compose contains vault service entry"
contains "$COMPOSE" 'hashicorp/vault:1.19' "vault service uses Vault image"
contains "$COMPOSE" 'dcapx_vault:' "compose has dcapx_vault volume"
contains "$COMPOSE" 'dcapx_vault_file:' "compose has dcapx_vault_file volume"

echo "[INFO] Running docker compose config"
if (cd "$ROOT" && docker compose config >/tmp/dcapx-vault-fix-compose.out); then
  pass "docker compose config passes"
else
  cat /tmp/dcapx-vault-fix-compose.out || true
  fail "docker compose config passes"
fi

echo "[INFO] Starting vault service"
if (cd "$ROOT" && docker compose up -d vault >/tmp/dcapx-vault-fix-up.out 2>&1); then
  pass "docker compose up -d vault passes"
else
  cat /tmp/dcapx-vault-fix-up.out || true
  fail "docker compose up -d vault passes"
fi

sleep 3

if (cd "$ROOT" && docker compose ps vault | grep -q "vault"); then
  pass "vault container is running"
else
  fail "vault container is running"
fi

HTTP_CODE="$(curl -s -o /tmp/dcapx-vault-fix-health.out -w "%{http_code}" http://127.0.0.1:8200/v1/sys/health || true)"
case "$HTTP_CODE" in
  200|429|472|473|501|503)
    pass "vault HTTP health endpoint is reachable (status $HTTP_CODE)"
    ;;
  *)
    echo "[INFO] Unexpected Vault health response code: $HTTP_CODE"
    [ -f /tmp/dcapx-vault-fix-health.out ] && cat /tmp/dcapx-vault-fix-health.out
    fail "vault HTTP health endpoint is reachable"
    ;;
esac

echo
echo "Resolved repo root: $ROOT"
echo "All Vault service placement fix checks passed."
