#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

echo "==> Backing up BFF files..."
backup apps/web/app/api/positions/route.ts
backup apps/web/app/api/open-orders/[symbol]/route.ts

mkdir -p apps/web/app/api/positions
mkdir -p apps/web/app/api/open-orders/[symbol]
mkdir -p scripts

echo "==> Writing authenticated positions BFF ..."
cat > apps/web/app/api/positions/route.ts <<'EOF'
import { NextResponse } from "next/server";
import { cookies } from "next/headers";

async function resolveUserId(base: string): Promise<string | null> {
  const jar = cookies();
  const sess = jar.get("dcapx_session")?.value;
  if (!sess) return null;

  const r = await fetch(`${base}/api/auth/session`, {
    cache: "no-store",
    headers: {
      Cookie: `dcapx_session=${sess}`,
      Accept: "application/json",
    },
  });

  if (!r.ok) return null;

  const data = await r.json().catch(() => null);
  return data?.user?.id ?? null;
}

export async function GET(req: Request) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);
  const mode = url.searchParams.get("mode") ?? "PAPER";

  const userId = await resolveUserId(base);

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
      userId,
      balances,
      positions: balances,
      items: balances,
    },
    { status: 200 }
  );
}
EOF

echo "==> Writing authenticated open-orders BFF ..."
cat > apps/web/app/api/open-orders/[symbol]/route.ts <<'EOF'
import { NextResponse } from "next/server";
import { cookies } from "next/headers";

async function resolveUserId(base: string): Promise<string | null> {
  const jar = cookies();
  const sess = jar.get("dcapx_session")?.value;
  if (!sess) return null;

  const r = await fetch(`${base}/api/auth/session`, {
    cache: "no-store",
    headers: {
      Cookie: `dcapx_session=${sess}`,
      Accept: "application/json",
    },
  });

  if (!r.ok) return null;

  const data = await r.json().catch(() => null);
  return data?.user?.id ?? null;
}

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const symbol = ctx.params.symbol;
  const limit = url.searchParams.get("limit") ?? "50";
  const mode = url.searchParams.get("mode") ?? "PAPER";

  const userId = await resolveUserId(base);

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
      userId,
      orders,
      items: orders,
    },
    { status: 200 }
  );
}
EOF

echo "==> Writing seed script ..."
cat > scripts/seed_demo_paper_market.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose exec -T pg psql -U dcapx -d dcapx <<'SQL'
DO $$
DECLARE
  uid text;
  btc_buy bigint;
  btc_sell bigint;
  rvai_buy bigint;
  rvai_sell bigint;
  t_buy bigint;
  t_sell bigint;
BEGIN
  SELECT id INTO uid
  FROM "User"
  WHERE email = 'pedro.vx.km@gmail.com';

  IF uid IS NULL THEN
    RAISE EXCEPTION 'User pedro.vx.km@gmail.com not found';
  END IF;

  -- clean recent demo paper rows for these symbols
  DELETE FROM "Trade"
  WHERE symbol IN ('BTC-USD', 'RVAI-USD')
    AND mode = 'PAPER'::"TradeMode"
    AND createdAt > now() - interval '7 days';

  DELETE FROM "Order"
  WHERE symbol IN ('BTC-USD', 'RVAI-USD')
    AND mode = 'PAPER'::"TradeMode"
    AND createdAt > now() - interval '7 days';

  -- balances for Pedro so positions panel has something to show
  INSERT INTO "Balance" ("userId","asset","amount","mode")
  VALUES
    (uid, 'USD',  '250000', 'PAPER'::"TradeMode"),
    (uid, 'BTC',  '1.2500', 'PAPER'::"TradeMode"),
    (uid, 'RVAI', '50000',  'PAPER'::"TradeMode")
  ON CONFLICT ("userId","mode","asset")
  DO UPDATE SET amount = EXCLUDED.amount;

  -- open orders for BTC-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','BUY'::"OrderSide",70850.00,0.20000000,'OPEN'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '3 minutes');

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','SELL'::"OrderSide",70950.00,0.18000000,'OPEN'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '2 minutes');

  -- open orders for RVAI-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','BUY'::"OrderSide",1.12000000,8000.00000000,'OPEN'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '3 minutes');

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','SELL'::"OrderSide",1.18000000,7500.00000000,'OPEN'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '2 minutes');

  -- trade 1: BTC-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','BUY'::"OrderSide",70910.00,0.05000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '15 minutes')
  RETURNING id INTO t_buy;

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','SELL'::"OrderSide",70910.00,0.05000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '15 minutes')
  RETURNING id INTO t_sell;

  INSERT INTO "Trade" ("symbol","price","qty","createdAt","mode","buyOrderId","sellOrderId")
  VALUES ('BTC-USD',70910.00,0.05000000,now() - interval '15 minutes','PAPER'::"TradeMode",t_buy,t_sell);

  -- trade 2: BTC-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','BUY'::"OrderSide",70883.19,0.04000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '6 minutes')
  RETURNING id INTO t_buy;

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','SELL'::"OrderSide",70883.19,0.04000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '6 minutes')
  RETURNING id INTO t_sell;

  INSERT INTO "Trade" ("symbol","price","qty","createdAt","mode","buyOrderId","sellOrderId")
  VALUES ('BTC-USD',70883.19,0.04000000,now() - interval '6 minutes','PAPER'::"TradeMode",t_buy,t_sell);

  -- trade 1: RVAI-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','BUY'::"OrderSide",1.14000000,1200.00000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '12 minutes')
  RETURNING id INTO t_buy;

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','SELL'::"OrderSide",1.14000000,1200.00000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '12 minutes')
  RETURNING id INTO t_sell;

  INSERT INTO "Trade" ("symbol","price","qty","createdAt","mode","buyOrderId","sellOrderId")
  VALUES ('RVAI-USD',1.14000000,1200.00000000,now() - interval '12 minutes','PAPER'::"TradeMode",t_buy,t_sell);

  -- trade 2: RVAI-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','BUY'::"OrderSide",1.16000000,900.00000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '4 minutes')
  RETURNING id INTO t_buy;

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','SELL'::"OrderSide",1.16000000,900.00000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '4 minutes')
  RETURNING id INTO t_sell;

  INSERT INTO "Trade" ("symbol","price","qty","createdAt","mode","buyOrderId","sellOrderId")
  VALUES ('RVAI-USD',1.16000000,900.00000000,now() - interval '4 minutes','PAPER'::"TradeMode",t_buy,t_sell);

END $$;
SQL

echo "✅ Demo PAPER market seeded for BTC-USD and RVAI-USD"
EOF

chmod +x scripts/seed_demo_paper_market.sh

echo
echo "==> Rebuilding web..."
pnpm --filter web build

echo
echo "✅ Private BFF patch + seed script written."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
echo "  bash scripts/seed_demo_paper_market.sh"
echo "  hard refresh /markets/BTC-USD and /markets/RVAI-USD"
