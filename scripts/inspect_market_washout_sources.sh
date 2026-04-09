#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Likely washout-related classes in market components"
rg -n 'bg-white/|bg-slate|absolute|relative|inset-0|pointer-events-none|backdrop|z-[0-9]+|opacity-|text-slate-|text-white/|Open Orders|Positions|Candles|1m|5m|1h|1d|createChart|applyOptions|layout:|textColor|watermark|crosshair|priceScale|timeScale' \
  apps/web/components/market || true

echo
echo "==> CandlesPanel top"
sed -n '1,260p' apps/web/components/market/CandlesPanel.tsx || true

echo
echo "==> CandlesPanel middle"
sed -n '260,520p' apps/web/components/market/CandlesPanel.tsx || true

echo
echo "==> MarketScreen top"
sed -n '1,320p' apps/web/components/market/MarketScreen.tsx || true

echo
echo "==> MarketScreen middle"
sed -n '320,760p' apps/web/components/market/MarketScreen.tsx || true
