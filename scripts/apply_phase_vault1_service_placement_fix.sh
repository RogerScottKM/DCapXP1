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

text = compose_path.read_text()

# Remove any previously inserted vault blocks at either root or service indentation.
patterns = [
    r'(?ms)^  vault:\n(?:^    .*\n|^      .*\n|^        .*\n|^\n)*',
    r'(?ms)^vault:\n(?:^  .*\n|^    .*\n|^      .*\n|^\n)*',
]
for pattern in patterns:
    text = re.sub(pattern, '', text)

vault_block = dedent("""\
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

m = re.search(r'(?m)^services:\n', text)
if not m:
    raise SystemExit("Could not find root services: block in docker-compose.yml")

insert_pos = m.end()
text = text[:insert_pos] + vault_block + text[insert_pos:]

# Ensure root volumes exist.
if "dcapx_vault:" not in text or "dcapx_vault_file:" not in text:
    if re.search(r'(?m)^volumes:\n', text):
        text = re.sub(
            r'(?m)^volumes:\n',
            'volumes:\n  dcapx_vault:\n  dcapx_vault_file:\n',
            text,
            count=1,
        )
    else:
        text = text.rstrip() + "\n\nvolumes:\n  dcapx_vault:\n  dcapx_vault_file:\n"

compose_path.write_text(text)
print("Repositioned the vault service under the root services block and ensured root Vault volumes exist.")
PY

echo "Resolved repo root: $ROOT"
echo "Vault service placement fix applied."
