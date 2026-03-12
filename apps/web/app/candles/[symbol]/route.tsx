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
  createdAt?: string;
  ts?: string;
};

function buildCandlesFromTrades(trades: TradeLike[], periodSec: number) {
  const rows = (trades ?? [])
    .map((t) => {
      const ts = t.createdAt ?? t.ts;
      const ms = ts ? Date.parse(ts) : NaN;
      return { ms, price: Number(t.price), qty: Number(t.qty) };
    })
    .filter((x) => Number.isFinite(x.ms) && Number.isFinite(x.price) && Number.isFinite(x.qty))
    .sort((a, b) => a.ms - b.ms);

  const m = new Map<number, { t: number; o: number; h: number; l: number; c: number; v: number }>();

  for (const r of rows) {
    const b = toMsBucket(r.ms, periodSec);
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

  return Array.from(m.values()).sort((a, b) => a.t - b.t);
}

async function fetchCoinbaseCandles(symbol: string, period: string) {
  const granularity = PERIOD_SEC[period];
  if (!granularity) throw new Error("Bad period");

  const url = `https://api.exchange.coinbase.com/products/${encodeURIComponent(symbol)}/candles?granularity=${granularity}`;

  const r = await fetch(url, {
    cache: "no-store",
    headers: { "user-agent": "dcapx-web", accept: "application/json" },
  });

  if (!r.ok) throw new Error(`coinbase ${r.status}`);
  const arr = (await r.json()) as any[];

  return arr
    .map((x) => ({
      t: Number(x[0]) * 1000,
      l: Number(x[1]),
      h: Number(x[2]),
      o: Number(x[3]),
      c: Number(x[4]),
      v: Number(x[5]),
    }))
    .reverse();
}

/**
 * Robust: get trades from SSE stream snapshot
 */
async function fetchTradesFromSseSnapshot(symbol: string, mode: string, tradeLimit: number) {
  const API_INTERNAL = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url =
    `${API_INTERNAL}/v1/stream/${encodeURIComponent(symbol)}` +
    `?depth=1&level=2&mode=${encodeURIComponent(mode)}` +
    `&limit=${tradeLimit}`;

  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 2500);

  try {
    const r = await fetch(url, {
      cache: "no-store",
      headers: { accept: "text/event-stream" },
      signal: ac.signal,
    });

    if (!r.ok || !r.body) return [] as TradeLike[];

    const reader = r.body.getReader();
    const decoder = new TextDecoder();

    let buf = "";
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;

      buf += decoder.decode(value, { stream: true });

      const parts = buf.split("\n\n");
      buf = parts.pop() ?? "";

      for (const block of parts) {
        const lines = block.split("\n").map((s) => s.trimEnd());
        const eventLine = lines.find((l) => l.startsWith("event:"));
        const eventName = eventLine ? eventLine.slice("event:".length).trim() : "";

        if (eventName !== "snapshot") continue;

        const dataLines = lines
          .filter((l) => l.startsWith("data:"))
          .map((l) => l.slice("data:".length).trim());

        const dataStr = dataLines.join("\n");

        try {
          const payload = JSON.parse(dataStr);
          const trades = payload?.trades ?? payload?.data?.trades ?? [];
          return Array.isArray(trades) ? (trades as TradeLike[]) : [];
        } catch {
          return [];
        }
      }
    }

    return [];
  } catch {
    return [];
  } finally {
    clearTimeout(timer);
  }
}

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const symbol = decodeURIComponent(ctx.params.symbol);
  const u = new URL(req.url);

  const period = u.searchParams.get("period") ?? "1m";
  const mode = (u.searchParams.get("mode") ?? "LIVE").toUpperCase();
  const source = (u.searchParams.get("source") ?? "auto").toLowerCase();

  const sec = PERIOD_SEC[period];
  if (!sec) return NextResponse.json({ ok: false, error: "Bad period" }, { status: 400 });

  const candleLimit = Math.min(Number(u.searchParams.get("limit") ?? "300") || 300, 2000);
  const tradeLimit = Math.min(Math.max(candleLimit * 50, 500), 20000);

  // Coinbase first (BTC/ETH/etc)
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

  // SSE trades snapshot
  let trades = await fetchTradesFromSseSnapshot(symbol, mode, tradeLimit);

  // fallback LIVE -> PAPER if needed
  let usedMode = mode;
  if (!trades.length && mode === "LIVE") {
    trades = await fetchTradesFromSseSnapshot(symbol, "PAPER", tradeLimit);
    if (trades.length) usedMode = "PAPER";
  }

  const candles = buildCandlesFromTrades(trades, sec);

  // ALWAYS 200 (no more console 404)
  return NextResponse.json({
    ok: true,
    symbol,
    source: "dcapx-sse",
    mode: usedMode,
    period,
    tradesFound: trades.length,
    candles,
    ...(candles.length ? {} : { error: "NotFound" }),
  });
}
