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
GITIGNORE_FILE="${ROOT}/.gitignore"
COMPOSE_FILE="${ROOT}/docker-compose.yml"

mkdir -p "${BOOTSTRAP_DIR}"
chmod 700 "${BOOTSTRAP_DIR}"

eval "$(
python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import shlex
import sys
from urllib.parse import quote

root = Path(sys.argv[1])

def parse_env_file(path: Path):
    data = {}
    if not path.exists():
        return data
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        data[key.strip()] = value
    return data

root_env = parse_env_file(root / ".env")
api_env = parse_env_file(root / "apps/api/.env")

def first_value(*keys, default=""):
    for key in keys:
        if api_env.get(key):
            return api_env[key]
        if root_env.get(key):
            return root_env[key]
    return default

def parse_password_from_url(url: str) -> str:
    if not url:
        return ""
    m = re.match(r'^[a-z]+://[^:]+:([^@]+)@', url)
    return m.group(1) if m else ""

pg_user = first_value("POSTGRES_USER", default="dcapx")
pg_password = first_value("POSTGRES_PASSWORD", default=parse_password_from_url(api_env.get("DATABASE_URL", "")))
pg_db = first_value("POSTGRES_DB", default="dcapx")
if not pg_password:
    raise SystemExit("Could not determine POSTGRES_PASSWORD from .env or apps/api/.env")

jwt_secret = first_value("JWT_SECRET")
otp_hmac_secret = first_value("OTP_HMAC_SECRET")
mfa_totp_issuer = first_value("MFA_TOTP_ISSUER", default="DCapX")
mfa_totp_encryption_key = first_value("MFA_TOTP_ENCRYPTION_KEY")
admin_key = first_value("ADMIN_KEY")
app_base_url = first_value("APP_BASE_URL", default="http://localhost:3000")
app_cors_origins = first_value("APP_CORS_ORIGINS", default="http://localhost:3000")
email_provider = first_value("EMAIL_PROVIDER", default="console")
email_from = first_value("EMAIL_FROM", default="DCapX <no-reply@dcapitalx.local>")
resend_api_key = first_value("RESEND_API_KEY")

enc_pw = quote(pg_password, safe="")
host_db_url = f"postgresql://{pg_user}:{enc_pw}@127.0.0.1:5445/{pg_db}?schema=public"
container_db_url = f"postgresql://{pg_user}:{enc_pw}@pg:5432/{pg_db}?schema=public"

values = {
    "HOST_DB_URL": host_db_url,
    "CONTAINER_DB_URL": container_db_url,
    "JWT_SECRET": jwt_secret,
    "OTP_HMAC_SECRET": otp_hmac_secret,
    "MFA_TOTP_ISSUER": mfa_totp_issuer,
    "MFA_TOTP_ENCRYPTION_KEY": mfa_totp_encryption_key,
    "ADMIN_KEY": admin_key,
    "APP_BASE_URL": app_base_url,
    "APP_CORS_ORIGINS": app_cors_origins,
    "EMAIL_PROVIDER": email_provider,
    "EMAIL_FROM": email_from,
    "RESEND_API_KEY": resend_api_key,
}
for k, v in values.items():
    print(f"{k}={shlex.quote(v)}")
PY
)"

cd "${ROOT}"
docker compose up -d vault >/tmp/dcapx-vault2-up.out 2>&1

for _ in $(seq 1 20); do
  code="$(curl -s -o /tmp/dcapx-vault2-health.out -w "%{http_code}" http://127.0.0.1:8200/v1/sys/health || true)"
  case "$code" in 200|429|472|473|501|503) break ;; esac
  sleep 1
done

if [[ ! -f "${INIT_FILE}" ]]; then
  docker compose exec -T vault sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 vault operator init -key-shares=1 -key-threshold=1 -format=json' > "${INIT_FILE}"
  chmod 600 "${INIT_FILE}"
fi

eval "$(
python3 - "${INIT_FILE}" <<'PY'
import json, shlex, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
print(f"ROOT_TOKEN={shlex.quote(data['root_token'])}")
print(f"UNSEAL_KEY={shlex.quote(data['unseal_keys_b64'][0])}")
PY
)"

STATUS_JSON="$(docker compose exec -T vault sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 vault status -format=json' 2>/dev/null || true)"
SEALED="$(STATUS_JSON="$STATUS_JSON" python3 - <<'PY'
import json, os
raw = os.environ.get("STATUS_JSON", "")
try:
    print("true" if json.loads(raw).get("sealed") else "false")
except Exception:
    print("false")
PY
)"
if [[ "${SEALED}" == "true" ]]; then
  docker compose exec -T -e UNSEAL_KEY="${UNSEAL_KEY}" vault sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal "$UNSEAL_KEY"' >/tmp/dcapx-vault2-unseal.out
fi

vcli() {
  docker run --rm --network host     -e VAULT_ADDR="http://127.0.0.1:8200"     -e VAULT_TOKEN="${ROOT_TOKEN}"     hashicorp/vault:1.19 vault "$@"
}

if ! vcli auth list -format=json | grep -q '"approle/"'; then
  vcli auth enable approle
fi

if ! vcli secrets list -format=json | grep -q '"secret/"'; then
  vcli secrets enable --version=2 --path=secret kv
fi

HOST_POLICY="$(mktemp)"
CONTAINER_POLICY="$(mktemp)"
cat > "${HOST_POLICY}" <<'EOF'
path "secret/data/dcapx/api-host" {
  capabilities = ["read"]
}
path "secret/metadata/dcapx/api-host" {
  capabilities = ["read"]
}
EOF

cat > "${CONTAINER_POLICY}" <<'EOF'
path "secret/data/dcapx/api-container" {
  capabilities = ["read"]
}
path "secret/metadata/dcapx/api-container" {
  capabilities = ["read"]
}
EOF

chmod 644 "${HOST_POLICY}" "${CONTAINER_POLICY}"

docker run --rm --network host -u 0:0 -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="${ROOT_TOKEN}" -v "${HOST_POLICY}:/work/policy.hcl:ro" hashicorp/vault:1.19 vault policy write dcapx-host-cli /work/policy.hcl >/tmp/dcapx-host-policy.out
docker run --rm --network host -u 0:0 -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="${ROOT_TOKEN}" -v "${CONTAINER_POLICY}:/work/policy.hcl:ro" hashicorp/vault:1.19 vault policy write dcapx-api-container /work/policy.hcl >/tmp/dcapx-container-policy.out

vcli write auth/approle/role/dcapx-host-cli token_policies="dcapx-host-cli" token_type="batch" secret_id_ttl="720h" token_ttl="1h" token_max_ttl="24h" secret_id_num_uses=0 >/tmp/dcapx-host-role.out
vcli write auth/approle/role/dcapx-api-container token_policies="dcapx-api-container" token_type="batch" secret_id_ttl="720h" token_ttl="1h" token_max_ttl="24h" secret_id_num_uses=0 >/tmp/dcapx-container-role.out

HOST_ROLE_ID="$(vcli read -field=role_id auth/approle/role/dcapx-host-cli/role-id)"
CONTAINER_ROLE_ID="$(vcli read -field=role_id auth/approle/role/dcapx-api-container/role-id)"

vcli write -field=secret_id -f auth/approle/role/dcapx-host-cli/secret-id > "${HOST_SECRET_FILE}"
vcli write -field=secret_id -f auth/approle/role/dcapx-api-container/secret-id > "${CONTAINER_SECRET_FILE}"
chmod 600 "${HOST_SECRET_FILE}" "${CONTAINER_SECRET_FILE}"

HOST_ARGS=(kv put -mount=secret dcapx/api-host "DATABASE_URL=${HOST_DB_URL}" "JWT_SECRET=${JWT_SECRET}" "OTP_HMAC_SECRET=${OTP_HMAC_SECRET}" "MFA_TOTP_ISSUER=${MFA_TOTP_ISSUER}" "APP_BASE_URL=${APP_BASE_URL}" "APP_CORS_ORIGINS=${APP_CORS_ORIGINS}" "EMAIL_PROVIDER=${EMAIL_PROVIDER}" "EMAIL_FROM=${EMAIL_FROM}")
CONTAINER_ARGS=(kv put -mount=secret dcapx/api-container "DATABASE_URL=${CONTAINER_DB_URL}" "JWT_SECRET=${JWT_SECRET}" "OTP_HMAC_SECRET=${OTP_HMAC_SECRET}" "MFA_TOTP_ISSUER=${MFA_TOTP_ISSUER}" "APP_BASE_URL=${APP_BASE_URL}" "APP_CORS_ORIGINS=${APP_CORS_ORIGINS}" "EMAIL_PROVIDER=${EMAIL_PROVIDER}" "EMAIL_FROM=${EMAIL_FROM}")
[[ -n "${MFA_TOTP_ENCRYPTION_KEY}" ]] && HOST_ARGS+=("MFA_TOTP_ENCRYPTION_KEY=${MFA_TOTP_ENCRYPTION_KEY}") && CONTAINER_ARGS+=("MFA_TOTP_ENCRYPTION_KEY=${MFA_TOTP_ENCRYPTION_KEY}")
[[ -n "${ADMIN_KEY}" ]] && HOST_ARGS+=("ADMIN_KEY=${ADMIN_KEY}") && CONTAINER_ARGS+=("ADMIN_KEY=${ADMIN_KEY}")
[[ -n "${RESEND_API_KEY}" ]] && HOST_ARGS+=("RESEND_API_KEY=${RESEND_API_KEY}") && CONTAINER_ARGS+=("RESEND_API_KEY=${RESEND_API_KEY}")

vcli "${HOST_ARGS[@]}" >/tmp/dcapx-host-kv.out
vcli "${CONTAINER_ARGS[@]}" >/tmp/dcapx-container-kv.out

cat > "${HOST_ENV_FILE}" <<EOF
VAULT_ENABLED=true
VAULT_ADDR=http://127.0.0.1:8200
VAULT_MOUNT_PATH=approle
VAULT_ROLE_ID=${HOST_ROLE_ID}
VAULT_SECRET_ID_FILE=${HOST_SECRET_FILE}
VAULT_SECRET_PATH=secret/data/dcapx/api-host
VAULT_OVERRIDE_ENV=true
EOF
chmod 600 "${HOST_ENV_FILE}"

cat > "${CONTAINER_ENV_FILE}" <<EOF
VAULT_ENABLED=true
VAULT_ADDR=http://vault:8200
VAULT_MOUNT_PATH=approle
VAULT_ROLE_ID=${CONTAINER_ROLE_ID}
VAULT_SECRET_ID_FILE=/run/secrets/dcapx-api-container.secret-id
VAULT_SECRET_PATH=secret/data/dcapx/api-container
VAULT_OVERRIDE_ENV=true
EOF
chmod 600 "${CONTAINER_ENV_FILE}"

python3 - "${COMPOSE_FILE}" <<'PY'
from pathlib import Path
import re
import sys

compose_path = Path(sys.argv[1])
text = compose_path.read_text()

if 'VAULT_BOOTSTRAP_FILE: /run/secrets/dcapx-api-container.env' not in text:
    text = re.sub(
        r'(^\s{8}VAULT_OVERRIDE_ENV: .*?$)',
        r'
        VAULT_BOOTSTRAP_FILE: /run/secrets/dcapx-api-container.env',
        text,
        count=1,
        flags=re.M,
    )

if './.env.vault.container:/run/secrets/dcapx-api-container.env:ro' not in text:
    api_match = re.search(r'(?ms)^  api:
(.*?)(?=^  [A-Za-z0-9_-]+:|\Z)', text)
    if not api_match:
        raise SystemExit("Could not locate api service block")
    block = api_match.group(0)
    if re.search(r'(?m)^\s{4}volumes:\s*$', block):
        block = re.sub(
            r'(?m)^(\s{4}volumes:\s*)$',
            r'
      - ./.env.vault.container:/run/secrets/dcapx-api-container.env:ro
      - ${HOME}/.dcapx-vault/api-container.secret-id:/run/secrets/dcapx-api-container.secret-id:ro',
            block,
            count=1,
        )
    else:
        block = block.rstrip() + "
    volumes:
      - ./.env.vault.container:/run/secrets/dcapx-api-container.env:ro
      - ${HOME}/.dcapx-vault/api-container.secret-id:/run/secrets/dcapx-api-container.secret-id:ro
"
    text = text.replace(api_match.group(0), block, 1)

compose_path.write_text(text)
PY

touch "${GITIGNORE_FILE}"
grep -qxF ".env.vault.host" "${GITIGNORE_FILE}" || echo ".env.vault.host" >> "${GITIGNORE_FILE}"
grep -qxF ".env.vault.container" "${GITIGNORE_FILE}" || echo ".env.vault.container" >> "${GITIGNORE_FILE}"

rm -f "${HOST_POLICY}" "${CONTAINER_POLICY}"

echo "Initialized/unsealed Vault, created host/container AppRoles, generated secret-id files in ${BOOTSTRAP_DIR}, wrote .env.vault.host + .env.vault.container, patched docker-compose api for container bootstrap, and seeded Vault paths dcapx/api-host + dcapx/api-container."
echo "Resolved repo root: ${ROOT}"
echo "Phase Vault-2 init/seed patch applied."
