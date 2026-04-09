#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

FILE="apps/web/components/market/MarketScreen.tsx"
backup "$FILE"

python3 - <<'PY'
from pathlib import Path

p = Path("apps/web/components/market/MarketScreen.tsx")
text = p.read_text()

old_block = """  const midPrice = useMemo(() => {
    const bestBid = orderbook?.bids?.[0] ? Number(orderbook.bids[0].price) : undefined;
    const bestAsk = orderbook?.asks?.[0] ? Number(orderbook.asks[0].price) : undefined;
    if (bestBid != null && bestAsk != null) return (bestBid + bestAsk) / 2;
    return lastPrice;
  }, [orderbook, lastPrice]);
"""

new_block = """  const midPrice = useMemo(() => {
    const bestBid = orderbook?.bids?.[0] ? Number(orderbook.bids[0].price) : undefined;
    const bestAsk = orderbook?.asks?.[0] ? Number(orderbook.asks[0].price) : undefined;
    if (bestBid != null && bestAsk != null) return (bestBid + bestAsk) / 2;
    return lastPrice;
  }, [orderbook, lastPrice]);

  const hasSnapshotData =
    (orderbook?.bids?.length ?? 0) > 0 ||
    (orderbook?.asks?.length ?? 0) > 0 ||
    trades.length > 0 ||
    midPrice != null ||
    lastPrice != null;

  const badgeTone =
    status === "live"
      ? "bg-emerald-400"
      : hasSnapshotData
        ? "bg-amber-400"
        : status === "error"
          ? "bg-rose-400"
          : "bg-slate-500";

  const badgeLabel =
    status === "live"
      ? "LIVE"
      : hasSnapshotData
        ? "SNAPSHOT"
        : status === "error"
          ? "ERROR"
          : "IDLE";
"""

if old_block not in text:
    raise SystemExit("Could not find midPrice block to patch")

text = text.replace(old_block, new_block)

old_jsx = """                <span
                  className={`h-2 w-2 rounded-full ${
                    status === "live" ? "bg-emerald-400" : status === "error" ? "bg-rose-400" : "bg-slate-500"
                  }`}
                />
                <span className="uppercase">{status === "live" ? "Live" : status}</span>
"""

new_jsx = """                <span className={`h-2 w-2 rounded-full ${badgeTone}`} />
                <span className="uppercase">{badgeLabel}</span>
"""

if old_jsx not in text:
    raise SystemExit("Could not find badge JSX block to patch")

text = text.replace(old_jsx, new_jsx)

p.write_text(text)
print("Patched apps/web/components/market/MarketScreen.tsx")
PY

echo
echo "==> Rebuilding web ..."
pnpm --filter web build

echo
echo "✅ MarketScreen SNAPSHOT badge patch applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
echo "  hard refresh:"
echo "    https://dcapitalx.com/markets/BTC-USD"
echo "    https://dcapitalx.com/markets/RVAI-USD"
