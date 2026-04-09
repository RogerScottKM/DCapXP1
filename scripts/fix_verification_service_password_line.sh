#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/api/src/modules/verification/verification.service.ts"

cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/api/src/modules/verification/verification.service.ts")
text = p.read_text()

text = text.replace(
    'data: { apps/api/prisma/schema.prisma:passwordHash: passwordHash },',
    'data: { passwordHash },'
)

# extra cleanup in case the malformed token appears slightly differently
text = re.sub(
    r'data:\s*\{\s*apps/api/prisma/schema\.prisma:passwordHash:\s*passwordHash\s*\},',
    'data: { passwordHash },',
    text
)

p.write_text(text)
print("Patched verification.service.ts")
PY

pnpm --filter api build
