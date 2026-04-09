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

# 1) Replace old helper signature if present
text = text.replace(
    "function prependRvaiHistory(candles: any[], period?: string): any[] {",
    "function prependRvaiHistory(candles: any[]): any[] {"
)

# 2) Replace old stepMs line with inferred spacing
text = text.replace(
    "  const stepMs = candlePeriodToMs(period);\n",
    """  let stepMs = 5 * 60_000;
  if (candles.length >= 2) {
    const firstMsCandidate = timeToMs(readTimeValue(candles[0]));
    const secondMsCandidate = timeToMs(readTimeValue(candles[1]));
    const inferred =
      firstMsCandidate && secondMsCandidate
        ? Math.abs(secondMsCandidate - firstMsCandidate)
        : 0;
    if (Number.isFinite(inferred) && inferred > 0) {
      stepMs = inferred;
    }
  }\n"""
)

# 3) Replace old normalize helper signature if present
text = text.replace(
    "function normalizeSyntheticRvaiCandles(\n  candles: any[],\n  symbol: string,\n  period?: string\n): any[] {",
    "function normalizeSyntheticRvaiCandles(\n  candles: any[],\n  symbol: string\n): any[] {"
)

# 4) Replace old return call
text = text.replace(
    "  return prependRvaiHistory(normalized, period);\n",
    "  return prependRvaiHistory(normalized);\n"
)

# 5) Replace the injected displayCandles line that references period
text = re.sub(
    r'const displayCandles = useMemo\(\(\) => normalizeSyntheticRvaiCandles\(rawCandles as any\[\], symbol as string, period as string \| undefined\), \[rawCandles, symbol, period\]\);',
    'const displayCandles = useMemo(() => normalizeSyntheticRvaiCandles(rawCandles as any[], symbol as string), [rawCandles, symbol]);',
    text
)

# 6) Fallback: if line used different spacing but still references period
text = re.sub(
    r'const displayCandles = useMemo\(\(\) => normalizeSyntheticRvaiCandles\(rawCandles as any\[\], symbol as string, [^)]+\), \[rawCandles, symbol, [^\]]+\]\);',
    'const displayCandles = useMemo(() => normalizeSyntheticRvaiCandles(rawCandles as any[], symbol as string), [rawCandles, symbol]);',
    text
)

path.write_text(text)
print("Patched CandlesPanel.tsx successfully.")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ RVAI candle history patch repaired."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
