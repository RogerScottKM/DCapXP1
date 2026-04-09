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

old = '''function normalizeSyntheticRvaiCandles(
  candles: any[],
  symbol: string
): any[] {
  if (String(symbol) !== "RVAI-USD") return candles;
  if (!Array.isArray(candles) || candles.length === 0) return candles;

  const normalized = candles.map((candle) => clampRvaiWicks(candle));
  return prependRvaiHistory(normalized);
}'''

new = '''function normalizeSyntheticRvaiCandles(
  candles: any[],
  symbol: string
): any[] {
  if (String(symbol) !== "RVAI-USD") return candles;
  if (!Array.isArray(candles) || candles.length === 0) return candles;

  // Backend botFarm is now the single source of truth for RVAI history.
  // Keep only wick normalization here.
  return candles.map((candle) => clampRvaiWicks(candle));
}'''

if old not in text:
    print("Could not find exact normalizeSyntheticRvaiCandles block.")
    print("Please paste: sed -n '170,210p' apps/web/components/market/CandlesPanel.tsx")
    sys.exit(1)

text = text.replace(old, new, 1)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Verify frontend fake-prehistory call is gone ..."
rg -n 'prependRvaiHistory\\(normalized\\)|Backend botFarm is now the single source of truth' "$FILE" || true

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ RVAI frontend now follows backend history only."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
