import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

const PERIOD_SEC: Record<string, number> = {
  "1m": 60,
  "5m": 300,
  "1h": 3600,
  "1d": 86400,
};

function toMsBucket(tsMs: number, sec: number) {
  const bucketSec = Math.floor(tsMs / 1000 / sec) * sec;
  return bucketSec * 1000;
}

type TradeLike = {
  price: string | number;
  qty: string | number;
  createdAt?: string | number;
  ts?: string | number;
  time?: string | number;
  timestamp?: string | number;
};

function coerceMs(ts: unknown): number {
  if (typeof ts === "number") {
    // seconds vs ms
    return ts > 1e12 ? ts : ts * 1000;
  }
  if (typeof ts === "string") {
    const s = ts.trim();
    // numeric string?
    if (/^\d+$/.test(s)) {
      const n = Number(s);
      return n > 1e12 ? n : n * 1000;
    }
    const ms = Date.parse(s);
    return Number.isFinite(ms) ? ms : NaN;
  }
  return NaN;
}

function buildCandlesFromTradesWindow(
  trades: TradeLike[],
  periodSec: number,
  endMs: number,
  candleLimit: number
) {
  const bucketMs = periodSec * 1000;

  const rows = (trades ?? [])
    .map((t) => {
      const ts = t.createdAt ?? t.ts ?? t.time ?? t.timestamp;
      const ms = coerceMs(ts);
      return { ms, price: Number(t.price), qty: Number(t.qty) };
    })
    .filter((x) => Number.isFinite(x.ms) && Number.isFinite(x.price) && Number.isFinite(x.qty))
    .sort((a, b) => a.ms - b.ms);

  if (!rows.length) return [];

  const lastTradeMs = rows[rows.length - 1].ms;
  const endB = toMsBucket(lastTradeMs, periodSec);
  const startB = endB - (candleLimit - 1) * bucketMs;

  console.log("[buildCandlesFromTradesWindow]", {
    trades: rows.length,
    firstTrade: rows[0]?.ms,
    lastTrade: rows[rows.length - 1]?.ms,
    startB,
    endB,
  });

  // bucket -> OHLCV
  const m = new Map<number, { t: number; o: number; h: number; l: number; c: number; v: number }>();

  for (const r of rows) {
    const b = toMsBucket(r.ms, periodSec);
    if (b < startB || b > endB) continue;

    const cur = m.get(b);
    if (!cur) {
      m.set(b, { t: b, o: r.price, h: r.price, l: r.price, c: r.price, v: r.qty });
    } else {
      cur.h = Math.max(cur.h, r.price);
      cur.l = Math.min(cur.l, r.price);
      cur.c = r.price;
      cur.v += r.qty;
    }
  }

  const first = Array.from(m.values()).sort((a, b) => a.t - b.t)[0];
  let lastClose: number | null = first?.o ?? null;

  const out: { t: number; o: number; h: number; l: number; c: number; v: number }[] = [];

  for (let b = startB; b <= endB; b += bucketMs) {
    const c = m.get(b);
    if (c) {
      lastClose = c.c;
      out.push(c);
    } else if (lastClose != null) {
      out.push({ t: b, o: lastClose, h: lastClose, l: lastClose, c: lastClose, v: 0 });
    }
  }

  return out.slice(-candleLimit);
}


async function fetchCoinbaseCandles(symbol: string, period: string) {
  const granularity = PERIOD_SEC[period];
  if (!granularity) throw new Error("Bad period");

  const url = `https://api.exchange.coinbase.com/products/${encodeURIComponent(
    symbol
  )}/candles?granularity=${granularity}`;

  const r = await fetch(url, {
    cache: "no-store",
    headers: { "user-agent": "dcapx-web", accept: "application/json" },
  });

  if (!r.ok) throw new Error(`coinbase ${r.status}`);
  const arr = (await r.json()) as any[];

  // Coinbase returns newest-first: [ time, low, high, open, close, volume ]
  const candles = arr
    .map((x) => ({
      t: Number(x[0]) * 1000,
      l: Number(x[1]),
      h: Number(x[2]),
      o: Number(x[3]),
      c: Number(x[4]),
      v: Number(x[5]),
    }))
    .reverse();

  return candles;
}

async function fetchDcapxTrades(
  symbol: string,
  mode: string,
  limit: number,
  sinceMs?: number
) {
  const API = process.env.API_INTERNAL_URL ?? "http://api:4010";

  const qs = new URLSearchParams();
  qs.set("symbol", symbol);
  qs.set("mode", mode);
  qs.set("limit", String(limit));
  if (sinceMs) qs.set("sinceMs", String(sinceMs));

  const urls = [
    `${API}/api/v1/market/trades?${qs.toString()}`,
    `${API}/api/v1/market/trades?${qs.toString().replace("sinceMs=", "fromMs=")}`,
    `${API}/api/v1/market/trades?${qs.toString().replace("sinceMs=", "afterMs=")}`,
  ];

  let lastError = "";

  for (const url of urls) {
    try {
      const r = await fetch(url, { cache: "no-store" });
      if (!r.ok) {
        lastError = `${url} -> ${r.status}`;
        continue;
      }

      const j = await r.json();
      const list =
        j?.items ??
        j?.trades ??
        j?.data?.items ??
        j?.data?.trades ??
        [];

      if (Array.isArray(list)) return list as TradeLike[];
    } catch (e: any) {
      lastError = `${url} -> ${String(e?.message ?? e)}`;
    }
  }

  console.error("[fetchDcapxTrades] failed", { symbol, mode, limit, sinceMs, lastError });
  return [];
}


export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const symbol = decodeURIComponent(ctx.params.symbol);
  const u = new URL(req.url);

  const period = u.searchParams.get("period") ?? "1m";
  const mode = (u.searchParams.get("mode") ?? "LIVE").toUpperCase();
  const source = (u.searchParams.get("source") ?? "auto").toLowerCase();

const isRvaiPaper = symbol === "RVAI-USD" && mode === "PAPER";

const requestedLimit = Number(u.searchParams.get("limit") ?? (isRvaiPaper ? "3000" : "300"));

const candleLimit = Math.min(
  Number.isFinite(requestedLimit) && requestedLimit > 0
    ? requestedLimit
    : (isRvaiPaper ? 3000 : 300),
  isRvaiPaper ? 4000 : 2000
);

const sec = PERIOD_SEC[period];
if (!sec) {
  return NextResponse.json({ ok: false, error: "Bad period" }, { status: 400 });
}

const endMs = Date.now();
const startMs = endMs - candleLimit * sec * 1000;

// For RVAI PAPER, allow a much larger trade window so seeded history is not truncated away
const tradeLimit = isRvaiPaper
  ? 120000
  : Math.min(Math.max(candleLimit * 200, 2000), 20000);


  // AUTO / Coinbase
  if (source === "coinbase" || source === "auto") {
    try {
      const candles = await fetchCoinbaseCandles(symbol, period);
      if (candles?.length) {
        return NextResponse.json({ ok: true, symbol, source: "coinbase", period, candles });
      }
    } catch {
      // fall through
    }
  }

  // DCapX fallback
  const trades = await fetchDcapxTrades(symbol, mode, tradeLimit, startMs);
  const candles = buildCandlesFromTradesWindow(trades, sec, endMs, candleLimit);

/**  const trades = await fetchDcapxTrades(u.origin, symbol, mode, limit); */
/**  const candles = buildCandlesFromTrades(trades, sec); */

if (!candles.length) {
  return NextResponse.json({
    ok: true,
    symbol,
    source: "dcapx",
    mode,
    period,
    tradesFound: trades.length,
    candles: [],
  });
}

  return NextResponse.json({
    ok: true,
    symbol,
    source: "dcapx",
    mode,
    period,
    tradesFound: trades.length,
    candles,
  });
}
