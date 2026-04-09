#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

echo "==> Backing up files..."
backup apps/api/src/app.ts
backup apps/web/app/api/positions/route.ts
backup apps/web/app/api/orderbook/[symbol]/route.ts
backup apps/web/app/api/trades/[symbol]/route.ts
backup apps/web/app/api/open-orders/[symbol]/route.ts || true
backup apps/web/app/api/stream/mode/[mode]/[symbol]/route.ts || true
backup apps/web/app/api/stream/symbol/[symbol]/route.ts || true

echo "==> Patching apps/api/src/app.ts ..."
python3 - <<'PY'
from pathlib import Path
p = Path("apps/api/src/app.ts")
text = p.read_text()

imports = {
    'import marketRoutes from "./routes/market";': 'marketRoutes',
    'import streamRoutes from "./routes/stream";': 'streamRoutes',
    'import tradeRoutes from "./routes/trade";': 'tradeRoutes',
}

lines = text.splitlines()
import_insert_at = 0
for i, ln in enumerate(lines):
    if ln.startswith("import "):
        import_insert_at = i + 1

for imp in imports:
    if imp not in text:
        lines.insert(import_insert_at, imp)
        import_insert_at += 1

text = "\n".join(lines)

mounts = """
// exchange / market compatibility mounts
app.use("/v1/market", marketRoutes);
app.use("/api/v1/market", marketRoutes);
app.use("/v1/stream", streamRoutes);
app.use("/api/v1/stream", streamRoutes);

// optional legacy naked mounts for existing local callers
app.use(marketRoutes);
app.use(streamRoutes);
app.use(tradeRoutes);
""".strip()

if 'app.use("/v1/market", marketRoutes);' not in text:
    marker = "// Global error handler"
    if marker in text:
        text = text.replace(marker, mounts + "\n\n" + marker)
    else:
        text += "\n\n" + mounts + "\n"

p.write_text(text)
PY

echo "==> Writing positions BFF ..."
mkdir -p apps/web/app/api/positions
cat > apps/web/app/api/positions/route.ts <<'EOF'
import { NextResponse } from "next/server";

export async function GET(req: Request) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);
  const mode = url.searchParams.get("mode") ?? "PAPER";
  const userId = url.searchParams.get("userId");

  const upstream = new URL(`${base}/v1/market/positions`);
  upstream.searchParams.set("mode", mode);
  if (userId) upstream.searchParams.set("userId", userId);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const raw = await r.text();

  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned non-JSON for positions",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamBodyPreview: raw.slice(0, 1000),
      },
      { status: 502 }
    );
  }

  const balances = Array.isArray(data.balances) ? data.balances : [];
  return NextResponse.json(
    {
      ok: true,
      mode,
      balances,
      items: balances,
      positions: balances,
      userId: data.userId ?? null,
    },
    { status: 200 }
  );
}
EOF

echo "==> Writing orderbook BFF ..."
mkdir -p apps/web/app/api/orderbook/[symbol]
cat > apps/web/app/api/orderbook/[symbol]/route.ts <<'EOF'
import { NextResponse } from "next/server";

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const symbol = ctx.params.symbol;
  const depth = url.searchParams.get("depth") ?? "20";
  const level = url.searchParams.get("level") ?? "2";
  const mode = url.searchParams.get("mode") ?? "PAPER";

  const upstream = new URL(`${base}/v1/market/orderbook`);
  upstream.searchParams.set("symbol", symbol);
  upstream.searchParams.set("depth", depth);
  upstream.searchParams.set("level", level);
  upstream.searchParams.set("mode", mode);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const raw = await r.text();

  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned non-JSON for orderbook",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamBodyPreview: raw.slice(0, 1000),
      },
      { status: 502 }
    );
  }

  const bids = Array.isArray(data.bids) ? data.bids : [];
  const asks = Array.isArray(data.asks) ? data.asks : [];

  const bestBid = bids.length ? bids[0] : null;
  const bestAsk = asks.length ? asks[0] : null;

  return NextResponse.json(
    {
      ok: true,
      symbol,
      mode,
      bids,
      asks,
      bestBid,
      bestAsk,
      level: data.level ?? Number(level),
      depth: Number(depth),
    },
    { status: 200 }
  );
}
EOF

echo "==> Writing trades BFF ..."
mkdir -p apps/web/app/api/trades/[symbol]
cat > apps/web/app/api/trades/[symbol]/route.ts <<'EOF'
import { NextResponse } from "next/server";

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const symbol = ctx.params.symbol;
  const limit = url.searchParams.get("limit") ?? "50";
  const mode = url.searchParams.get("mode") ?? "PAPER";

  const upstream = new URL(`${base}/v1/market/trades`);
  upstream.searchParams.set("symbol", symbol);
  upstream.searchParams.set("limit", limit);
  upstream.searchParams.set("mode", mode);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const raw = await r.text();

  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned non-JSON for trades",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamBodyPreview: raw.slice(0, 1000),
      },
      { status: 502 }
    );
  }

  const trades = Array.isArray(data.trades) ? data.trades : [];
  return NextResponse.json(
    {
      ok: true,
      symbol,
      mode,
      trades,
      items: trades,
      limit: Number(limit),
    },
    { status: 200 }
  );
}
EOF

if [ -d apps/web/app/api/open-orders/[symbol] ]; then
  echo "==> Writing open-orders BFF ..."
  mkdir -p apps/web/app/api/open-orders/[symbol]
  cat > apps/web/app/api/open-orders/[symbol]/route.ts <<'EOF'
import { NextResponse } from "next/server";

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const symbol = ctx.params.symbol;
  const limit = url.searchParams.get("limit") ?? "50";
  const mode = url.searchParams.get("mode") ?? "PAPER";
  const userId = url.searchParams.get("userId");

  const upstream = new URL(`${base}/v1/market/open-orders`);
  upstream.searchParams.set("symbol", symbol);
  upstream.searchParams.set("limit", limit);
  upstream.searchParams.set("mode", mode);
  if (userId) upstream.searchParams.set("userId", userId);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const raw = await r.text();

  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned non-JSON for open-orders",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamBodyPreview: raw.slice(0, 1000),
      },
      { status: 502 }
    );
  }

  const orders = Array.isArray(data.orders) ? data.orders : [];
  return NextResponse.json(
    {
      ok: true,
      symbol,
      mode,
      orders,
      items: orders,
      limit: Number(limit),
    },
    { status: 200 }
  );
}
EOF
fi

if [ -d apps/web/app/api/stream/mode/[mode]/[symbol] ]; then
  echo "==> Writing stream BFF (mode route) ..."
  mkdir -p apps/web/app/api/stream/mode/[mode]/[symbol]
  cat > apps/web/app/api/stream/mode/[mode]/[symbol]/route.ts <<'EOF'
export async function GET(
  _req: Request,
  ctx: { params: { mode: string; symbol: string } }
) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = `${base}/v1/stream/${encodeURIComponent(ctx.params.symbol)}?mode=${encodeURIComponent(ctx.params.mode)}`;

  const upstream = await fetch(url, {
    cache: "no-store",
    headers: { Accept: "text/event-stream" },
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
fi

if [ -d apps/web/app/api/stream/symbol/[symbol] ]; then
  echo "==> Writing stream BFF (symbol route) ..."
  mkdir -p apps/web/app/api/stream/symbol/[symbol]
  cat > apps/web/app/api/stream/symbol/[symbol]/route.ts <<'EOF'
export async function GET(
  _req: Request,
  ctx: { params: { symbol: string } }
) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = `${base}/v1/stream/${encodeURIComponent(ctx.params.symbol)}`;

  const upstream = await fetch(url, {
    cache: "no-store",
    headers: { Accept: "text/event-stream" },
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
fi

echo
echo "==> Rebuilding..."
pnpm --filter api build
pnpm --filter web build

echo
echo "✅ Market BFF phase 2 patch applied."
echo
echo "Next:"
echo "  docker compose build api web --no-cache"
echo "  docker compose up -d api web"
echo "  curl -i \"http://127.0.0.1:4010/v1/market/orderbook?symbol=BTC-USD&depth=20&mode=PAPER\""
echo "  curl -i \"http://127.0.0.1:4010/v1/market/trades?symbol=BTC-USD&limit=20&mode=PAPER\""
echo "  curl -i \"http://127.0.0.1:4010/v1/market/orderbook?symbol=RVAI-USD&depth=20&mode=PAPER\""
echo "  curl -i \"http://127.0.0.1:4010/v1/market/trades?symbol=RVAI-USD&limit=20&mode=PAPER\""
