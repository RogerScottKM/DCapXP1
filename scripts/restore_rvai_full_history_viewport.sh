#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="apps/web/components/market/CandlesPanel.tsx"
BACKUP="${FILE}.bak.$(date +%Y%m%d%H%M%S)}"
cp "$FILE" "$BACKUP"
echo "Backup created: $BACKUP"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/web/components/market/CandlesPanel.tsx")
s = p.read_text()
orig = s

# Replace the current viewport block with a deterministic RVAI full-history viewport.
pattern = re.compile(
    r'''
    const\ WINDOW\s*=\s*
    .*?
    const\ from\s*=\s*
    .*?;
    \s*
    const\ to\s*=\s*
    .*?;
    ''',
    re.DOTALL | re.VERBOSE
)

replacement = '''const WINDOW =
    symbol === "RVAI-USD"
      ? (
          tf === "1m" ? 2500 :
          tf === "5m" ? 600 :
          tf === "1h" ? 120 :
          200
        )
      : (
          tf === "1m" ? 120 :
          tf === "5m" ? 120 :
          tf === "1h" ? 200 :
          200
        );

  // For RVAI, always show the full loaded backend history window.
  // For other symbols, keep the recent focused viewport.
  const from =
    symbol === "RVAI-USD"
      ? 0
      : Math.max(0, lastActiveIndex - WINDOW + 1);

  const to =
    symbol === "RVAI-USD"
      ? Math.max(0, candles.length - 1)
      : Math.min(candles.length - 1, lastActiveIndex + 3);'''

new_s, n = pattern.subn(replacement, s, count=1)
if n != 1:
    raise SystemExit("[FAIL] Could not patch WINDOW/from/to block in CandlesPanel.tsx")

p.write_text(new_s)
print("Patched CandlesPanel.tsx viewport for RVAI full-history display")
PY

echo
echo "==> Verify patch"
sed -n '560,610p' apps/web/components/market/CandlesPanel.tsx

echo
echo "==> Build check"
pnpm --filter web build

echo
echo "==> Rebuild + restart web"
docker compose build web --no-cache
docker compose up -d web

echo
echo "==> Recent web logs"
docker compose logs web --tail=80
