#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="apps/web/components/market/CandlesPanel.tsx"
cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)}"

python3 - <<'PY'
from pathlib import Path

p = Path("apps/web/components/market/CandlesPanel.tsx")
s = p.read_text()

old = '  const candles = normalizeCandles(rawCandles);'
new = '''  const plotSource =
    symbol === "RVAI-USD"
      ? normalizeSyntheticRvaiCandles(rawCandles as any[], symbol as string)
      : rawCandles;

  const candles = normalizeCandles(plotSource as any[]);'''

if old not in s:
    raise SystemExit("Could not find exact rawCandles normalize line to replace.")

s = s.replace(old, new, 1)
p.write_text(s)
print("Patched CandlesPanel.tsx")
PY

pnpm --filter web build
docker compose build web --no-cache
docker compose up -d web
