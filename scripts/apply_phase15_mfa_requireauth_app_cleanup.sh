#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

def must_read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")
    return path.read_text()

def write(path: Path, text: str) -> None:
    path.write_text(text)

def patch_env_example():
    p = root / ".env.example"
    s = must_read(p)
    if "MFA_TOTP_ISSUER=" not in s:
        s += "\nMFA_TOTP_ISSUER=DCapX\n"
    if "MFA_TOTP_ENCRYPTION_KEY=" not in s:
        s += "MFA_TOTP_ENCRYPTION_KEY=change-me\n"
    write(p, s)

def patch_compose(path_str: str):
    p = root / path_str
    s = must_read(p)
    if "MFA_TOTP_ISSUER:" in s:
        write(p, s)
        return

    patterns = [
        r'(\n\s+OTP_HMAC_SECRET:\s+\$\{OTP_HMAC_SECRET\}\n)',
        r'(\n\s+OTP_HMAC_SECRET:\s+\$\{OTP_HMAC_SECRET:-\}\n)',
        r'(\n\s+OTP_HMAC_SECRET:\s+\$\{OTP_HMAC_SECRET:-[^}]*\}\n)',
    ]

    replacement_block = (
        r'\1'
        '        MFA_TOTP_ISSUER: ${MFA_TOTP_ISSUER:-DCapX}\n'
        '        MFA_TOTP_ENCRYPTION_KEY: ${MFA_TOTP_ENCRYPTION_KEY:-}\n'
    )

    for pattern in patterns:
        new_s, n = re.subn(pattern, replacement_block, s, count=1)
        if n:
            write(p, new_s)
            return

    raise SystemExit(f"Could not patch {path_str}: OTP_HMAC_SECRET line not found")

def patch_package_json():
    p = root / "apps/api/package.json"
    s = must_read(p)
    if '"helmet"' not in s:
        s = s.replace('"node-vault": "^0.12.0"', '"node-vault": "^0.12.0",\n    "helmet": "^8.1.0"')
    if '"otplib"' not in s:
        s = s.replace('"helmet": "^8.1.0"', '"helmet": "^8.1.0",\n    "otplib": "^12.0.1"')
    write(p, s)

patch_env_example()
patch_compose("docker-compose.yml")
patch_compose("docker-compose.prod.yml")
patch_package_json()

print("Patched .env.example, docker-compose.yml, docker-compose.prod.yml, and apps/api/package.json")
PY

chmod +x "$ROOT/scripts/apply_phase15_mfa_requireauth_app_cleanup.sh"
echo "Compose/env/package patch pass completed."
