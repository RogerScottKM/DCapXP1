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

echo "==> Patching apps/api/src/app.ts to mount market/trade/stream routes ..."
python3 - <<'PY'
from pathlib import Path
p = Path("apps/api/src/app.ts")
text = p.read_text()

imports = [
    ('import marketRoutes from "./routes/market";', 'marketRoutes'),
    ('import tradeRoutes from "./routes/trade";', 'tradeRoutes'),
    ('import streamRoutes from "./routes/stream";', 'streamRoutes'),
]

for line, _ in imports:
    if line not in text:
        # insert after existing imports
        lines = text.splitlines()
        insert_at = 0
        for i, ln in enumerate(lines):
            if ln.startswith("import "):
                insert_at = i + 1
        lines.insert(insert_at, line)
        text = "\n".join(lines)

mount_block = """
// mount exchange/market routes
app.use(marketRoutes);
app.use(tradeRoutes);
app.use(streamRoutes);
""".strip()

if 'app.use(marketRoutes);' not in text:
    marker = '// Global error handler'
    if marker in text:
        text = text.replace(marker, mount_block + "\n\n  " + marker)
    else:
        text += "\n\n" + mount_block + "\n"

p.write_text(text)
PY

echo "==> Writing resilient BFF route: positions ..."
mkdir -p apps/web/app/api/positions
cat > apps/web/app/api/positions/route.ts <<'EOF'
import { NextResponse } from "next/server";

export async function GET(req: Request) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);
  const mode = url.searchParams.get("mode") ?? "PAPER";

  const upstream = new URL(`${base}/v1/market/positions`);
  upstream.searchParams.set("mode", mode);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const contentType = r.headers.get("content-type") ?? "";
  const raw = await r.text();

  if (r.status === 401 || r.status === 403 || r.status === 404) {
    return NextResponse.json({ ok: true, positions: [], items: [] }, { status: 200 });
  }

  if (!contentType.includes("application/json")) {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream did not return JSON",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamContentType: contentType,
        upstreamBodyPreview: raw.slice(0, 1200),
      },
      { status: 502 }
    );
  }

  try {
    const data = JSON.parse(raw);
    if (Array.isArray(data) ) {
      return NextResponse.json({ ok: true, positions: data, items: data }, { status: 200 });
    }
    if (!Array.isArray(data.positions)) data.positions = [];
    if (!Array.isArray(data.items)) data.items = data.positions;
    return NextResponse.json(data, { status: r.status });
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned invalid JSON",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamContentType: contentType,
        upstreamBodyPreview: raw.slice(0, 1200),
      },
      { status: 502 }
    );
  }
}
EOF

echo "==> Writing resilient BFF route: orderbook ..."
mkdir -p apps/web/app/api/orderbook/[symbol]
cat > apps/web/app/api/orderbook/[symbol]/route.ts <<'EOF'
import { NextResponse } from "next/server";

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const depth = url.searchParams.get("depth") ?? "20";
  const level = url.searchParams.get("level") ?? "2";
  const symbol = ctx.params.symbol;

  const upstream = new URL(`${base}/v1/market/orderbook`);
  upstream.searchParams.set("symbol", symbol);
  upstream.searchParams.set("depth", depth);
  upstream.searchParams.set("level", level);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const contentType = r.headers.get("content-type") ?? "";
  const raw = await r.text();

  if (r.status === 404) {
    return NextResponse.json(
      { ok: true, symbol, bids: [], asks: [], bestBid: null, bestAsk: null },
      { status: 200 }
    );
  }

  if (!contentType.includes("application/json")) {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream did not return JSON",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamContentType: contentType,
        upstreamBodyPreview: raw.slice(0, 1200),
      },
      { status: 502 }
    );
  }

  try {
    const data = JSON.parse(raw);
    if (!Array.isArray(data.bids)) data.bids = [];
    if (!Array.isArray(data.asks)) data.asks = [];
    return NextResponse.json(data, { status: r.status });
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned invalid JSON",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamContentType: contentType,
        upstreamBodyPreview: raw.slice(0, 1200),
      },
      { status: 502 }
    );
  }
}
EOF

echo "==> Writing resilient BFF route: trades ..."
mkdir -p apps/web/app/api/trades/[symbol]
cat > apps/web/app/api/trades/[symbol]/route.ts <<'EOF'
import { NextResponse } from "next/server";

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const limit = url.searchParams.get("limit") ?? "60";
  const symbol = ctx.params.symbol;

  const upstream = new URL(`${base}/v1/market/trades`);
  upstream.searchParams.set("symbol", symbol);
  upstream.searchParams.set("limit", limit);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const contentType = r.headers.get("content-type") ?? "";
  const raw = await r.text();

  if (r.status === 404) {
    return NextResponse.json({ ok: true, symbol, trades: [], items: [] }, { status: 200 });
  }

  if (!contentType.includes("application/json")) {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream did not return JSON",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamContentType: contentType,
        upstreamBodyPreview: raw.slice(0, 1200),
      },
      { status: 502 }
    );
  }

  try {
    const data = JSON.parse(raw);
    if (Array.isArray(data.trades) && !Array.isArray(data.items)) {
      data.items = data.trades;
    }
    if (!Array.isArray(data.trades) && Array.isArray(data.items)) {
      data.trades = data.items;
    }
    if (!Array.isArray(data.trades)) data.trades = [];
    if (!Array.isArray(data.items)) data.items = data.trades;
    return NextResponse.json(data, { status: r.status });
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned invalid JSON",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamContentType: contentType,
        upstreamBodyPreview: raw.slice(0, 1200),
      },
      { status: 502 }
    );
  }
}
EOF

if [ -f apps/web/app/api/open-orders/[symbol]/route.ts ]; then
  echo "==> Writing temporary safe BFF route: open-orders ..."
  cat > apps/web/app/api/open-orders/[symbol]/route.ts <<'EOF'
import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({ ok: true, orders: [], items: [] }, { status: 200 });
}
EOF
fi

echo
echo "==> Rebuilding..."
pnpm --filter api build
pnpm --filter web build

echo
echo "✅ Phase-1 market BFF patch written."
echo
echo "Next:"
echo "  docker compose build api web --no-cache"
echo "  docker compose up -d api web"
echo "  curl -i https://dcapitalx.com/api/positions"
echo "  curl -i \"https://dcapitalx.com/api/orderbook/BTC-USD?mode=PAPER&depth=20\""
echo "  curl -i \"https://dcapitalx.com/api/trades/BTC-USD?limit=50\""
