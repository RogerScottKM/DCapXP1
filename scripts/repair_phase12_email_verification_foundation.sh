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
backup apps/api/src/modules/verification/verification.service.ts

echo "==> Deduping User verification fields in schema ..."
python3 - <<'PY'
from pathlib import Path
import re
import os

schema_path = Path("apps/api/prisma/schema.prisma")
text = schema_path.read_text()

m = re.search(r'model\s+User\s*\{(?P<body>.*?)\n\}', text, re.S)
if not m:
    raise SystemExit("Could not find model User in schema.prisma")

body = m.group("body")
lines = body.splitlines()

targets = {
    "emailVerifiedAt",
    "phoneVerifiedAt",
    "verificationChallenges",
    "notificationDeliveries",
}

seen = set()
new_lines = []
for line in lines:
    stripped = line.strip()
    if not stripped:
      new_lines.append(line)
      continue

    field = stripped.split()[0]
    if field in targets:
        if field in seen:
            continue
        seen.add(field)

    new_lines.append(line)

new_body = "\n".join(new_lines)
text = text[:m.start("body")] + new_body + text[m.end("body"):]
schema_path.write_text(text)

m2 = re.search(r'model\s+User\s*\{(?P<body>.*?)\n\}', text, re.S)
user_body = m2.group("body")

password_field = None
for candidate in ["passwordHash", "hashedPassword"]:
    if re.search(rf'^\s*{candidate}\b', user_body, re.M):
        password_field = candidate
        break

if not password_field:
    password_field = "passwordHash"

Path("/tmp/dcapx_password_field.txt").write_text(password_field)
print(f"Detected password field: {password_field}")
PY

PASSWORD_FIELD="$(cat /tmp/dcapx_password_field.txt)"
echo "Using password field: ${PASSWORD_FIELD}"

echo "==> Repairing verification.service.ts password update ..."
PASSWORD_FIELD="${PASSWORD_FIELD}" python3 - <<'PY'
from pathlib import Path
import os
import re

password_field = os.environ["PASSWORD_FIELD"]
p = Path("apps/api/src/modules/verification/verification.service.ts")
text = p.read_text()

# Replace any broken prisma.user.update in resetPassword with a clean version
pattern = r'''
prisma\.user\.update\(\{
\s*where:\s*\{\s*id:\s*challenge\.userId\s*\},
\s*data:\s*\{.*?passwordHash.*?\},
\s*\}\)
'''
replacement = f'''prisma.user.update({{
        where: {{ id: challenge.userId }},
        data: {{ {password_field}: passwordHash }},
      }})'''

text2, n = re.subn(pattern, replacement, text, count=1, flags=re.S | re.X)

if n == 0:
    # fallback for malformed generated field text
    text2, n = re.subn(
        r'prisma\.user\.update\(\{.*?challenge\.userId.*?passwordHash.*?\}\)',
        replacement,
        text,
        count=1,
        flags=re.S
    )

if n == 0:
    # final fallback: direct replace the exact malformed line shape if present
    text2 = re.sub(
        r'data:\s*\{\s*[^}]*passwordHash\s*:\s*passwordHash\s*\},',
        f'data: {{ {password_field}: passwordHash }},',
        text,
        count=1,
        flags=re.S
    )
else:
    pass

p.write_text(text2)
print("Patched verification.service.ts")
PY

echo
echo "==> Prisma format / validate ..."
pnpm --filter api prisma format
pnpm --filter api prisma validate

echo
echo "==> Type build ..."
pnpm --filter api build

echo
echo "✅ Repair complete."
echo
echo "Next:"
echo "  pnpm --filter api prisma migrate dev --name add_email_verification_foundation"
echo "  pnpm --filter api prisma generate"
echo "  docker compose build api web --no-cache"
echo "  docker compose up -d api web"
