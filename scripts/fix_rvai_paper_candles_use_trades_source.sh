#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/web/components/market/CandlesPanel.tsx"

if [ ! -f "$FILE" ]; then
  echo "Missing $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)}"

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("apps/web/components/market/CandlesPanel.tsx")
text = path.read_text()

# Insert source selector near URL building / fetch block.
needle = 'const base ='
if needle not in text:
    print("Could not find URL-building area. Please run:")
    print("rg -n 'source=auto|period=|limit=' apps/web/components/market/CandlesPanel.tsx")
    sys.exit(1)

# Best-effort targeted insertion if not already present
if 'const candleSource =' not in text:
    text = text.replace(
        needle,
        '''const candleSource =
    symbol === "RVAI-USD" && mode === "PAPER"
      ? "trades"
      : "auto";

  ''' + needle,
        1
    )

# Replace hardcoded source=auto in URL strings
text = text.replace('source=auto', 'source=${candleSource}')

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Verify patch"
rg -n 'candleSource|source=\\$\\{candleSource\\}|source=auto' "$FILE" || true

echo
echo "==> Build check"
pnpm --filter web build

echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
