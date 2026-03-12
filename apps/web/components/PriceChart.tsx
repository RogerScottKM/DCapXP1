'use client';

import {
  createChart,
  ColorType,
  type IChartApi,
  type CandlestickData,
  type HistogramData,
  type UTCTimestamp,
} from 'lightweight-charts';
import { useEffect, useRef } from 'react';

type Candle = { t: number; o: number; h: number; l: number; c: number; v: number };

export default function PriceChart({ symbol }: { symbol: string }) {
  const elRef = useRef<HTMLDivElement | null>(null);
  const chartRef = useRef<IChartApi | null>(null);

  useEffect(() => {
    if (!elRef.current) return;

    const chart = createChart(elRef.current, {
      layout: {
        background: { type: ColorType.Solid, color: '#0f172a' }, // <-- enum, not "solid"
        textColor: '#cbd5e1',
      },
      height: 420,
      timeScale: { borderColor: '#334155', rightOffset: 2 },
      // Candles on the right scale
      rightPriceScale: {
        visible: true,
        borderColor: '#334155',
        scaleMargins: { top: 0.06, bottom: 0.22 }, // room for wicks + volume bar area
      },
      // Volume on a separate (left) scale with tiny vertical space
      leftPriceScale: {
        visible: true,
        borderColor: '#334155',
        scaleMargins: { top: 0.8, bottom: 0.02 },
      },
      grid: { vertLines: { color: '#1f2937' }, horzLines: { color: '#1f2937' } },
    });
    chartRef.current = chart;

    const candles = chart.addCandlestickSeries({
      priceScaleId: 'right',
      upColor: '#10b981',
      downColor: '#ef4444',
      borderVisible: false,
      wickUpColor: '#10b981',
      wickDownColor: '#ef4444',
      priceFormat: { type: 'price', precision: 2, minMove: 0.01 },
    });

    const volume = chart.addHistogramSeries({
      priceScaleId: 'left',
      priceFormat: { type: 'volume' },
    });

    let abort = new AbortController();

    async function load() {
      const r = await fetch(`/api/candles/${symbol}`, { signal: abort.signal });
      const { candles: ks }: { candles: Candle[] } = await r.json();

      const c: CandlestickData[] = ks.map(k => ({
        time: (k.t / 1000) as UTCTimestamp,
        open: k.o, high: k.h, low: k.l, close: k.c,
      }));

      const v: HistogramData[] = ks.map((k, i, a) => {
        const prevClose = a[i - 1]?.c ?? k.o;
        const up = k.c >= prevClose;
        return {
          time: (k.t / 1000) as UTCTimestamp,
          value: Number(k.v || 0),
          color: up ? '#10b981' : '#ef4444',
        };
      });

      candles.setData(c);
      volume.setData(v);
      chart.timeScale().fitContent();
    }

    load();
    const id = setInterval(load, 10_000);

    const onResize = () => chart.applyOptions({ width: elRef.current!.clientWidth });
    window.addEventListener('resize', onResize);
    onResize();

    return () => {
      abort.abort();
      clearInterval(id);
      window.removeEventListener('resize', onResize);
      chart.remove();
    };
  }, [symbol]);

  return <div ref={elRef} className="w-full rounded-xl border border-slate-800" />;
}
