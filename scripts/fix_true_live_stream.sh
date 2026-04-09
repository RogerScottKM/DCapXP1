#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

backup apps/api/src/routes/stream.ts
backup apps/web/components/market/MarketScreen.tsx
mkdir -p apps/web/app/api/stream/[symbol]

echo "==> Patching backend stream route ..."
python3 - <<'PY'
from pathlib import Path

p = Path("apps/api/src/routes/stream.ts")
text = p.read_text()

old = 'router.get("/stream/:symbol", async (req, res) => {'
new = 'router.get("/:symbol", async (req, res) => {'

if old not in text:
    raise SystemExit("Could not find backend stream route signature to patch")

text = text.replace(old, new, 1)
p.write_text(text)
print("Patched apps/api/src/routes/stream.ts")
PY

echo "==> Writing Next SSE proxy route ..."
cat > apps/web/app/api/stream/[symbol]/route.ts <<'EOF'
export async function GET(
  req: Request,
  ctx: { params: { symbol: string } }
) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);
  const mode = url.searchParams.get("mode") ?? "PAPER";
  const symbol = encodeURIComponent(ctx.params.symbol);

  const upstreamUrl = `${base}/v1/stream/${symbol}?mode=${encodeURIComponent(mode)}`;

  const upstream = await fetch(upstreamUrl, {
    cache: "no-store",
    headers: {
      Accept: "text/event-stream",
    },
  });

  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      "Content-Type": upstream.headers.get("content-type") ?? "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      "Connection": "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}
EOF

echo "==> Patching MarketScreen EventSource URL ..."
python3 - <<'PY'
from pathlib import Path

p = Path("apps/web/components/market/MarketScreen.tsx")
text = p.read_text()

old = 'const url = `/api/stream/${encodeURIComponent(symbol)}`;'
new = 'const url = `/api/stream/${encodeURIComponent(symbol)}?mode=${encodeURIComponent(mode)}`;'

if old not in text:
    raise SystemExit("Could not find MarketScreen stream URL to patch")

text = text.replace(old, new, 1)
p.write_text(text)
print("Patched apps/web/components/market/MarketScreen.tsx")
PY

echo
echo "==> Rebuilding..."
pnpm --filter api build
pnpm --filter web build

echo
echo "✅ True LIVE stream patch applied."
echo
echo "Next:"
echo "  docker compose build api web --no-cache"
echo "  docker compose up -d api web"
echo
echo "Then test:"
echo '  curl -i -N --max-time 5 "http://127.0.0.1:4010/v1/stream/BTC-USD?mode=PAPER"'
echo '  curl -i -N --max-time 5 "https://dcapitalx.com/api/stream/BTC-USD?mode=PAPER"'
echo
echo "Then hard refresh:"
echo "  https://dcapitalx.com/markets/BTC-USD"
echo "  https://dcapitalx.com/markets/RVAI-USD"
