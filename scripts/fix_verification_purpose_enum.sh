#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

backup apps/api/prisma/schema.prisma

python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/api/prisma/schema.prisma")
text = p.read_text()

m = re.search(r'enum\s+VerificationPurpose\s*\{(?P<body>.*?)\n\}', text, re.S)
if not m:
    raise SystemExit("Could not find enum VerificationPurpose in schema.prisma")

body = m.group("body")
lines = [ln.rstrip() for ln in body.splitlines() if ln.strip()]
values = [ln.strip() for ln in lines]

wanted = ["CONTACT_VERIFICATION", "PASSWORD_RESET", "MFA"]

for item in wanted:
    if item not in values:
        values.append(item)

new_body = "\n" + "\n".join(f"  {v}" for v in values) + "\n"
text = text[:m.start("body")] + new_body + text[m.end("body"):]
p.write_text(text)

print("Patched VerificationPurpose enum:")
for v in values:
    print(" -", v)
PY

echo
echo "==> Prisma format / validate ..."
pnpm --filter api prisma format
pnpm --filter api prisma validate

echo
echo "==> Create/apply migration for enum update ..."
pnpm --filter api prisma migrate dev --name add_password_reset_to_verification_purpose

echo
echo "==> Regenerate Prisma client ..."
pnpm --filter api prisma generate

echo
echo "==> Type build check ..."
pnpm --filter api build

echo
echo "✅ VerificationPurpose enum fixed."
echo
echo "Next:"
echo "  docker compose build api web --no-cache"
echo "  docker compose up -d api web"
