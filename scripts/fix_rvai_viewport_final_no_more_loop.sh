#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/web/components/market/CandlesPanel.tsx"

if [ ! -f "$FILE" ]; then
  echo "Missing $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import sys

path = Path("apps/web/components/market/CandlesPanel.tsx")
text = path.read_text()

old_block = '''  const WINDOW =
    tf === "1m" ? 120 :
    tf === "5m" ? 120 :
    tf === "1h" ? 200 :
    200;

  // Focus the visible x-window around the active region,
  // instead of ending on the long flat synthetic tail
  const from = Math.max(0, lastActiveIndex - WINDOW + 1);
  const to = Math.min(candles.length - 1, lastActiveIndex + 3);'''

new_block = '''  const WINDOW =
    symbol === "RVAI-USD"
      ? (
          tf === "1m" ? 2400 :
          tf === "5m" ? 520 :
          tf === "1h" ? 72 :
          120
        )
      : (
          tf === "1m" ? 120 :
          tf === "5m" ? 120 :
          tf === "1h" ? 200 :
          200
        );

  // For RVAI, show the full loaded backend history.
  // For other symbols, keep the focused recent-window behaviour.
  const from =
    symbol === "RVAI-USD"
      ? 0
      : Math.max(0, lastActiveIndex - WINDOW + 1);

  const to =
    symbol === "RVAI-USD"
      ? Math.max(0, candles.length - 1)
      : Math.min(candles.length - 1, lastActiveIndex + 3);'''

if old_block not in text:
    print("Could not find exact WINDOW/from/to block.")
    print("Paste: sed -n '528,555p' apps/web/components/market/CandlesPanel.tsx")
    sys.exit(1)

text = text.replace(old_block, new_block, 1)

old_spacing = '        barSpacing: issuerControlled ? 14 : 8,'
new_spacing = '''        barSpacing:
          symbol === "RVAI-USD"
            ? (tf === "1m" ? 2 : tf === "5m" ? 4 : 8)
            : issuerControlled
            ? 14
            : 8,'''
if old_spacing in text:
    text = text.replace(old_spacing, new_spacing, 1)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Verify patch ..."
sed -n '528,560p' "$FILE" || true

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ RVAI viewport patch applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
