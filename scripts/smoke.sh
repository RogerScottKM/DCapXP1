#!/usr/bin/env bash
set -euo pipefail

echo "1) api health"
curl -fsS http://127.0.0.1:4010/health >/dev/null && echo "OK"

echo "2) web health"
curl -fsS http://127.0.0.1:3000/api/health >/dev/null && echo "OK"

echo "3) markets"
curl -fsS http://127.0.0.1:4010/v1/markets | head -c 120 && echo

echo "4) candles"
curl -fsS "http://127.0.0.1:4010/api/v1/market/candles?symbol=BTC-USD&period=24h" | head -c 120 && echo

echo "5) exchange page"
curl -fsS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3000/exchange/BTC-USD
