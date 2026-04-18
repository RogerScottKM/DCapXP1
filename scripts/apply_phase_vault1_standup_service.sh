#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1])
compose_path = root / "docker-compose.yml"
config_dir = root / "infra/vault/config"
config_path = config_dir / "vault.hcl"
readme_path = root / "infra/vault/README.md"

if not compose_path.exists():
    raise SystemExit(f"Missing required file: {compose_path}")

config_dir.mkdir(parents=True, exist_ok=True)
config_path.write_text(dedent("""ui = true
disable_mlock = true

storage "raft" {
  path    = "/vault/data"
  node_id = "dcapx-vault-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 1
}

api_addr     = "http://vault:8200"
cluster_addr = "http://vault:8201"
log_level    = "info"
"""))

readme_path.write_text(dedent("""# DCapX Vault

This folder holds the configuration for the DCapX Vault service.

Current mode:
- non-dev Vault server
- persistent single-node Raft storage
- local HTTP listener on 127.0.0.1:8200 via Docker port binding

This is a production-like bootstrap for DCapX development and pre-production hardening.

Still recommended before real production rollout:
- TLS certificates
- auto-unseal
- 3-node HA Raft cluster
- audit shipping / monitoring
"""))

compose_text = compose_path.read_text()

if not re.search(r'(?m)^  vault:\s*$', compose_text):
    vault_service = dedent("""\

  vault:
    image: hashicorp/vault:1.19
    cap_add:
      - IPC_LOCK
    command: ["vault", "server", "-config=/vault/config/vault.hcl"]
    ports:
      - "127.0.0.1:8200:8200"
    volumes:
      - ./infra/vault/config:/vault/config:ro
      - dcapx_vault:/vault/data
      - dcapx_vault_file:/vault/file
    networks:
      - app
    restart: unless-stopped
""")
    anchor = "\nvolumes:\n"
    if anchor not in compose_text:
        raise SystemExit("Could not find volumes anchor in docker-compose.yml")
    compose_text = compose_text.replace(anchor, vault_service + anchor, 1)

if "dcapx_vault:" not in compose_text or "dcapx_vault_file:" not in compose_text:
    compose_text = compose_text.replace(
        "volumes:\n  dcapx_pg:\n  dcapx_redis:\n",
        "volumes:\n  dcapx_pg:\n  dcapx_redis:\n  dcapx_vault:\n  dcapx_vault_file:\n",
        1,
    )

if "infra/vault/config:/vault/config:ro" not in compose_text:
    raise SystemExit("Vault service patch did not land correctly")

compose_path.write_text(compose_text)
print("Patched docker-compose.yml with a persistent non-dev Vault service and wrote infra/vault/config/vault.hcl + README.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase Vault-1 service stand-up patch applied."
