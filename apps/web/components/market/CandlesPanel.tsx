"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createChart, CandlestickData, UTCTimestamp, ISeriesApi } from "lightweight-charts";

type Tf = "1m" | "5m" | "1h" | "1d";
type Mode = "LIVE" | "PAPER";

function normalizeCandles(raw: any[]): CandlestickData[] {
  return (raw ?? [])
    .map((x: any) => {
      const t = x.t ?? x.time ?? x.ts ?? x.start ?? x.startMs ?? x.timestamp ?? x.createdAt;

      const timeSec =
        typeof t === "number"
          ? Math.floor(t > 1e12 ? t / 1000 : t) // ms -> s
          : Math.floor(Date.parse(String(t)) / 1000);

      const o = Number(x.o ?? x.open);
      const h = Number(x.h ?? x.high);
      const l = Number(x.l ?? x.low);
      const c = Number(x.c ?? x.close);

      if (!Number.isFinite(timeSec) || timeSec <= 0) return null;
      if (![o, h, l, c].every(Number.isFinite)) return null;

      return { time: timeSec as UTCTimestamp, open: o, high: h, low: l, close: c };
    })
    .filter(Boolean) as CandlestickData[];
}

export default function CandlesPanel({ symbol, mode }: { symbol: string; mode: Mode }) {
  const [tf, setTf] = useState<Tf>("5m");
  const [err, setErr] = useState<string | null>(null);

  const didSetInitialRangeRef = useRef(false);

  const ref = useRef<HTMLDivElement | null>(null);
  const chartRef = useRef<ReturnType<typeof createChart> | null>(null);
  const seriesRef = useRef<ISeriesApi<"Candlestick"> | null>(null);

  const tfs: Tf[] = useMemo(() => ["1m", "5m", "1h", "1d"], []);

  // ✅ INSERT THIS RIGHT HERE
  useEffect(() => {
    didSetInitialRangeRef.current = false;
  }, [symbol, mode, tf]);


  // Create chart ONCE
  useEffect(() => {
    if (!ref.current) return;

    ref.current.innerHTML = "";
    const chart = createChart(ref.current, {
      width: ref.current.clientWidth,
      height: 320,
      layout: { background: { color: "transparent" }, textColor: "#cbd5e1" },
      grid: { vertLines: { visible: false }, horzLines: { visible: false } },
      rightPriceScale: { borderVisible: false },
      timeScale: { borderVisible: false },
      crosshair: { mode: 1 },
    });

const lowPrice = /^(RVAI|RVGX|APTV)-/i.test(symbol);

const series = chart.addCandlestickSeries(
  lowPrice
    ? {
        upColor: "#10b981",
        downColor: "#f43f5e",
        wickUpColor: "#10b981",
        wickDownColor: "#f43f5e",
        borderVisible: false,
        priceFormat: {
          type: "price",
          precision: 6,
          minMove: 0.000001,
        },
      }
    : {
        upColor: "#10b981",
        downColor: "#f43f5e",
        wickUpColor: "#10b981",
        wickDownColor: "#f43f5e",
        borderVisible: false,
      }
);
    chartRef.current = chart;
    seriesRef.current = series;

    const ro = new ResizeObserver(() => {
      chart.applyOptions({ width: ref.current!.clientWidth });
    });
    ro.observe(ref.current);

    return () => {
      ro.disconnect();
      chart.remove();
      chartRef.current = null;
      seriesRef.current = null;
    };
  }, [symbol]);

  // Load candles when symbol/tf/mode changes
  useEffect(() => {
    let alive = true;
    setErr(null);

async function load() {
  
  const limit =
    tf === "1m" ? 1500 :   // ~25 hours
    tf === "5m" ? 2000 :   // ~6.9 days
    tf === "1h" ? 2000 :   // ~83 days
    2000;

  const issuerControlled = /^(RVAI|RVGX|APTV)-/i.test(symbol);
  const source = issuerControlled ? "dcapx" : "auto";

  const base = `/api/candles/${encodeURIComponent(symbol)}?period=${tf}&source=${source}&limit=${limit}`;  

  async function fetchJson(url: string) {
    const r = await fetch(url, { cache: "no-store" });
    const text = await r.text();

    // Some endpoints accidentally stream/append multiple JSON objects.
    // Try strict parse first; if it fails, take the first JSON object.
    let j: any;
    try {
      j = JSON.parse(text);
    } catch {
      const idx = text.indexOf("}{");
      if (idx !== -1) j = JSON.parse(text.slice(0, idx + 1));
      else throw new Error(`Bad JSON: ${text.slice(0, 120)}`);
    }

    return { r, j };
  }

  // For issuer-controlled markets, use the selected mode directly.
  // For external markets like BTC, PAPER can still prefer LIVE first.
  const primaryMode: Mode =
    issuerControlled ? mode : (mode === "PAPER" ? "LIVE" : mode);

  let { r, j } = await fetchJson(`${base}&mode=${primaryMode}`);
  console.log("[CandlesPanel:fetch]", {
  symbol,
  mode,
  tf,
  issuerControlled,
  source,
  primaryMode,
  ok: r.ok,
  error: j?.error,
  candleCount: Array.isArray(j?.candles) ? j.candles.length : 0,
  });

  // If preferred source has no real candles, fall back to the selected mode.
  const probeCandles = Array.isArray(j?.candles) ? j.candles : [];
  const hasActivity = probeCandles.some((c: any) => {
    const v = Number(c?.v ?? 0);
    const o = Number(c?.o ?? c?.open);
    const h = Number(c?.h ?? c?.high);
    const l = Number(c?.l ?? c?.low);
    const cl = Number(c?.c ?? c?.close);

    return (
      v > 0 ||
      (
        Number.isFinite(o) &&
        Number.isFinite(h) &&
        Number.isFinite(l) &&
        Number.isFinite(cl) &&
        (o !== cl || h !== l)
      )
    );
  });

  const noData =
    !r.ok ||
    j?.ok === false ||
    !Array.isArray(j?.candles) ||
    j.candles.length === 0 ||
    j?.error === "NotFound" ||
    !hasActivity;

if (noData && primaryMode !== mode) {
  ({ r, j } = await fetchJson(`${base}&mode=${mode}`));
}

const isArray = Array.isArray(j?.candles);
const candleLen = isArray ? j.candles.length : -1;
const jKeys = j && typeof j === "object" ? Object.keys(j) : [];

console.log(
  "[CandlesPanel:guard:flat]",
  "symbol=", symbol,
  "mode=", mode,
  "tf=", tf,
  "rOk=", r.ok,
  "jOk=", j?.ok,
  "isArray=", isArray,
  "candleLen=", candleLen,
  "keys=", jKeys,
  "sample=", typeof j === "object" ? JSON.stringify(j).slice(0, 220) : String(j)
);

if (!r.ok || j?.ok === false || !Array.isArray(j?.candles) || j.candles.length === 0) {
  console.log(
    "[CandlesPanel:empty-return:flat]",
    "symbol=", symbol,
    "mode=", mode,
    "tf=", tf,
    "rOk=", r.ok,
    "jOk=", j?.ok,
    "isArray=", isArray,
    "candleLen=", candleLen,
    "keys=", jKeys
  );

  setErr(null);
  seriesRef.current?.setData([]);
  chartRef.current?.timeScale().fitContent();
  return;
}
  const rawCandles = Array.isArray(j.candles) ? [...j.candles] : [];
  const activeCount = rawCandles.filter((c: any) => {
  const v = Number(c?.v ?? 0);
  const o = Number(c?.o ?? c?.open);
  const h = Number(c?.h ?? c?.high);
  const l = Number(c?.l ?? c?.low);
  const cl = Number(c?.c ?? c?.close);

  return (
    v > 0 ||
    (
      Number.isFinite(o) &&
      Number.isFinite(h) &&
      Number.isFinite(l) &&
      Number.isFinite(cl) &&
      (o !== cl || h !== l)
    )
  );
}).length;

console.log("[CandlesPanel:data]", {
  symbol,
  mode,
  tf,
  rawCount: rawCandles.length,
  activeCount,
  first: rawCandles[0],
  last: rawCandles[rawCandles.length - 1],
});

  // Keep raw + normalized candles in the same chronological order
  rawCandles.sort((a: any, b: any) => {
    const ta = Number(a?.t ?? a?.time ?? a?.ts ?? 0);
    const tb = Number(b?.t ?? b?.time ?? b?.ts ?? 0);
    return ta - tb;
  });

  const candles = normalizeCandles(rawCandles);

console.log("[CandlesPanel:data]", {
  symbol,
  mode,
  tf,
  rawCount: rawCandles.length,
  normalizedCount: candles.length,
  firstRaw: rawCandles[0],
  lastRaw: rawCandles[rawCandles.length - 1],
});

  const chart = chartRef.current;
  if (!chart || candles.length === 0) {
    seriesRef.current?.setData([]);
    return;
  }

  // Always feed the FULL candle set into the chart
  // Insert this test block! 16:49 10/03/2026 
  console.log("[CandlesPanel]", {
  symbol,
  mode,
  tf,
  issuerControlled,
  rawCount: rawCandles.length,
  normalizedCount: candles.length,
  sampleFirst: rawCandles[0],
  sampleLast: rawCandles[rawCandles.length - 1],
  });
  
  seriesRef.current?.setData(candles);

  // Find the last active candle index in the full series
  let lastActiveIndex = rawCandles.length - 1;

  for (let i = rawCandles.length - 1; i >= 0; i--) {
    const c = rawCandles[i];
    const v = Number(c?.v ?? 0);
    const o = Number(c?.o ?? c?.open);
    const h = Number(c?.h ?? c?.high);
    const l = Number(c?.l ?? c?.low);
    const cl = Number(c?.c ?? c?.close);

    const moved =
      Number.isFinite(o) &&
      Number.isFinite(h) &&
      Number.isFinite(l) &&
      Number.isFinite(cl) &&
      (o !== cl || h !== l);

    if (v > 0 || moved) {
      lastActiveIndex = i;
      break;
    }
  }

  const WINDOW =
    tf === "1m" ? 120 :
    tf === "5m" ? 120 :
    tf === "1h" ? 200 :
    200;

  // Focus the visible x-window around the active region,
  // instead of ending on the long flat synthetic tail
  const from = Math.max(0, lastActiveIndex - WINDOW + 1);
  const to = Math.min(candles.length - 1, lastActiveIndex + 3);

console.log("[CandlesPanel:plot]", {
  symbol,
  mode,
  tf,
  candleCount: candles.length,
  lastActiveIndex,
  from,
  to,
});

  requestAnimationFrame(() => {
    chart.applyOptions({
      timeScale: {
        rightOffset: 2,
        barSpacing: issuerControlled ? 14 : 8,
      },
    });

    chart.timeScale().setVisibleLogicalRange({ from, to });

    chart.priceScale("right").applyOptions({
      autoScale: true,
      scaleMargins: { top: 0.12, bottom: 0.12 },
    });
  });

}

    load().catch((e) => {
      if (!alive) return;
      setErr(String(e?.message ?? e));
      seriesRef.current?.setData([]);
    });

    return () => {
      alive = false;
    };
  }, [symbol, tf, mode]);

  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="text-sm text-slate-200">Candles</div>
        <div className="flex gap-2">
          {tfs.map((x) => (
            <button
              key={x}
              className={`rounded-lg px-3 py-1 text-xs ${tf === x ? "bg-white/15 text-white" : "bg-white/5 text-slate-300"}`}
              onClick={() => setTf(x)}
            >
              {x}
            </button>
          ))}
        </div>
      </div>

      {err ? (
        <div className="mb-3 rounded-xl border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-xs text-rose-200">
          Candles error: {err}
        </div>
      ) : null}

      <div ref={ref} />
    </div>
  );
}
