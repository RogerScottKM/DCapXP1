"use client";

import { useEffect, useState } from "react";
import type { Widget } from "@repo/schema/ui";

type Props = Extract<Widget, { type: "SimpleChart" }>;

export default function SimpleChartWidget({ symbol, period }: Props) {
  const [candles, setCandles] = useState<any[]>([]);

  useEffect(() => {
    const url = `/api/candles/${encodeURIComponent(symbol)}?period=${encodeURIComponent(
      period
    )}`;

    fetch(url)
      .then((r) => r.json())
      .then((d) => setCandles(d.candles ?? []))
      .catch(() => setCandles([]));
  }, [symbol, period]);

  const last = candles[candles.length - 1];

  return (
    <div className="border rounded p-4">
      <div className="font-semibold">
        Chart · {symbol} · {period}
      </div>
      <div className="text-sm opacity-80 mt-2">
        Candles: {candles.length} {last ? `| last close: ${last.c}` : ""}
      </div>
    </div>
  );
}
