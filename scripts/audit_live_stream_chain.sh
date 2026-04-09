#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Backend stream router"
if [ -f apps/api/src/routes/stream.ts ]; then
  cat -n apps/api/src/routes/stream.ts
else
  echo "Missing: apps/api/src/routes/stream.ts"
fi

echo
echo "==> API app mounts"
cat -n apps/api/src/app.ts

echo
echo "==> Web stream routes"
for f in \
  apps/web/app/api/stream/mode/[mode]/[symbol]/route.ts \
  apps/web/app/api/stream/symbol/[symbol]/route.ts \
  apps/web/app/wapi/stream/[symbol]/route.ts
do
  if [ -f "$f" ]; then
    echo "----- $f -----"
    cat -n "$f"
    echo
  fi
done

echo
echo "==> MarketScreen EventSource / stream references"
rg -n 'EventSource|/api/stream|/wapi/stream|/v1/stream|streamConnected|setStatus\("live"\)|setStatus\("error"\)' \
  apps/web/components/market/MarketScreen.tsx || true

echo
echo "==> Direct stream curls"
echo "--- local backend BTC ---"
curl -i -N --max-time 5 "http://127.0.0.1:4010/v1/stream/BTC-USD?mode=PAPER" || true
echo
echo "--- local backend RVAI ---"
curl -i -N --max-time 5 "http://127.0.0.1:4010/v1/stream/RVAI-USD?mode=PAPER" || true
echo
echo "--- site api stream BTC ---"
curl -i -N --max-time 5 "https://dcapitalx.com/api/stream/mode/PAPER/BTC-USD" || true
echo
echo "--- site api stream RVAI ---"
curl -i -N --max-time 5 "https://dcapitalx.com/api/stream/mode/PAPER/RVAI-USD" || true
echo
echo "--- site wapi stream BTC ---"
curl -i -N --max-time 5 "https://dcapitalx.com/wapi/stream/BTC-USD" || true
echo
echo "--- site wapi stream RVAI ---"
curl -i -N --max-time 5 "https://dcapitalx.com/wapi/stream/RVAI-USD" || true
