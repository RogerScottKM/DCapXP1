"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createChart, CandlestickData, UTCTimestamp } from "lightweight-charts";

type Tf = "1m" | "5m" | "1h" | "1d";

function normalizeCandles(raw: any[]): CandlestickData[] {
  // Supports multiple possible shapes:
  // { t, o, h, l, c } or { time, open, high, low, close }
  return (raw ?? [])
    .map((x: any) => {
      const t =
        x.t ?? x.time ?? x.ts ?? x.start ?? x.startMs ?? x.timestamp ?? x.createdAt;
      const timeSec =
        typeof t === "number"
          ? Math.floor(t > 1e12 ? t / 1000 : t)
          : Math.floor(Date.parse(String(t)) / 1000);

      const o = Number(x.o ?? x.open);
      const h = Number(x.h ?? x.high);
      const l = Number(x.l ?? x.low);
      const c = Number(x.c ?? x.close);

      if (!timeSec || !isFinite(o) || !isFinite(h) || !isFinite(l) || !isFinite(c)) return null;
      return { time: timeSec as UTCTimestamp, open: o, high: h, low: l, close: c };
    })
    .filter(Boolean) as CandlestickData[];
}

export default function CandlesPanel({ symbol }: { symbol: string }) {
  const [tf, setTf] = useState<Tf>("5m");
  const ref = useRef<HTMLDivElement | null>(null);
  const chartRef = useRef<ReturnType<typeof createChart> | null>(null);

  const tfs: Tf[] = useMemo(() => ["1m", "5m", "1h", "1d"], []);

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

    const series = chart.addCandlestickSeries();
    chartRef.current = chart;

    const ro = new ResizeObserver(() => {
      chart.applyOptions({ width: ref.current!.clientWidth });
    });
    ro.observe(ref.current);

    return () => {
      ro.disconnect();
      chart.remove();
      chartRef.current = null;
    };
  }, []);

  useEffect(() => {
    let alive = true;

    async function load() {
      const r = await fetch(`/api/candles/${encodeURIComponent(symbol)}?tf=${tf}`, {
        cache: "no-store",
      });
      const j = await r.json();

      // common shapes: { candles: [...] } or { items: [...] }
      const candles = normalizeCandles(j.candles ?? j.items ?? []);
      if (!alive || !chartRef.current) return;

      const s = chartRef.current.addCandlestickSeries();
      s.setData(candles);
    }

    load().catch(console.error);
    return () => {
      alive = false;
    };
  }, [symbol, tf]);

  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="text-sm text-slate-200">Candles</div>
        <div className="flex gap-2">
          {tfs.map((x) => (
            <button
              key={x}
              className={`rounded-lg px-3 py-1 text-xs ${
                tf === x ? "bg-white/15 text-white" : "bg-white/5 text-slate-300"
              }`}
              onClick={() => setTf(x)}
            >
              {x}
            </button>
          ))}
        </div>
      </div>
      <div ref={ref} />
    </div>
  );
}
