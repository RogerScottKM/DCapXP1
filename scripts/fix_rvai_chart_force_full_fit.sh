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
import re
import sys

path = Path("apps/web/components/market/CandlesPanel.tsx")
text = path.read_text()

anchor = '''  seriesRef.current?.setData(candles);

  // Find the last active candle index in the full series
  let lastActiveIndex = displayCandles.length - 1;'''

insert = '''  seriesRef.current?.setData(candles);

  if (symbol === "RVAI-USD") {
    requestAnimationFrame(() => {
      const chartNow = chartRef.current;
      if (!chartNow) return;

      chartNow.timeScale().fitContent();
      chartNow.timeScale().applyOptions({
        rightOffset: 2,
        barSpacing: tf === "1m" ? 2.2 : tf === "5m" ? 5.5 : tf === "1h" ? 8 : 10,
      });
    });

    console.log("[CandlesPanel:plot:rvai-fit]", {
      symbol,
      mode,
      tf,
      candleCount: candles.length,
      first: candles[0],
      last: candles[candles.length - 1],
    });

    return;
  }

  // Find the last active candle index in the full series
  let lastActiveIndex = displayCandles.length - 1;'''

if anchor not in text:
    print("Could not find exact insertion anchor.")
    print("Please paste: sed -n '508,545p' apps/web/components/market/CandlesPanel.tsx")
    sys.exit(1)

text = text.replace(anchor, insert, 1)

old_spacing = '        barSpacing: issuerControlled ? 14 : 8,'
new_spacing = '''        barSpacing:
          symbol === "RVAI-USD"
            ? (tf === "1m" ? 2.2 : tf === "5m" ? 5.5 : tf === "1h" ? 8 : 10)
            : issuerControlled
            ? 14
            : 8,'''
if old_spacing in text:
    text = text.replace(old_spacing, new_spacing, 1)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Verify patch"
rg -n 'CandlesPanel:plot:rvai-fit|barSpacing:|fitContent\\(' "$FILE" || true

echo
echo "==> Build check"
pnpm --filter web build

echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
