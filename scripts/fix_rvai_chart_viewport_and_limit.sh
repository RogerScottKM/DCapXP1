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

# 1) Increase candle fetch limit if present
text = text.replace("limit=2000", "limit=4000")
text = text.replace("limit: 2000", "limit: 4000")
text = text.replace("limit ?? 2000", "limit ?? 4000")

# 2) Reduce RVAI bar spacing so more candles fit horizontally
old_spacing = 'barSpacing: issuerControlled ? 14 : 8,'
new_spacing = 'barSpacing: symbol === "RVAI-USD" ? 5 : issuerControlled ? 14 : 8,'
if old_spacing in text:
    text = text.replace(old_spacing, new_spacing, 1)

# 3) For RVAI, fit full loaded history instead of forcing a narrow logical range
old_range = '    chart.timeScale().setVisibleLogicalRange({ from, to });'
new_range = '''    if (symbol === "RVAI-USD") {
      chart.timeScale().fitContent();
      chart.timeScale().applyOptions({
        rightOffset: 2,
        barSpacing: 5,
      });
    } else {
      chart.timeScale().setVisibleLogicalRange({ from, to });
    }'''
if old_range in text:
    text = text.replace(old_range, new_range, 1)
else:
    print("Could not find exact visible range line.")
    print("Please paste: sed -n '520,560p' apps/web/components/market/CandlesPanel.tsx")
    sys.exit(1)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Verify patch ..."
rg -n 'limit=4000|limit: 4000|barSpacing: symbol === "RVAI-USD" \? 5|fitContent\(\)|setVisibleLogicalRange' "$FILE" || true

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ RVAI chart viewport patch applied."
echo
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
