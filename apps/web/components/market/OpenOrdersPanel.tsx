"use client";

import { useEffect, useState } from "react";

export default function OpenOrdersPanel({ symbol }: { symbol: string }) {
  const [rows, setRows] = useState<any[]>([]);

  useEffect(() => {
    let alive = true;

    fetch(`/api/open-orders/${encodeURIComponent(symbol)}?limit=50`, { cache: "no-store" })
      .then((r) => r.json())
      .then((j) => alive && setRows(j.orders ?? []))
      .catch(console.error);

    const t = setInterval(() => {
      fetch(`/api/open-orders/${encodeURIComponent(symbol)}?limit=50`, { cache: "no-store" })
        .then((r) => r.json())
        .then((j) => alive && setRows(j.orders ?? []))
        .catch(() => {});
    }, 1500);

    return () => {
      alive = false;
      clearInterval(t);
    };
  }, [symbol]);

  return (
    <div className="rounded-2xl border border-slate-200 bg-white/80 p-4 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] dark:border-white/10 dark:bg-white/5 dark:shadow-none">
      <div className="mb-2 text-sm font-medium text-slate-700 dark:text-slate-200">Open Orders</div>
      <div className="max-h-64 overflow-auto text-xs">
        <div className="grid grid-cols-5 gap-2 pb-2 text-slate-500 dark:text-slate-400">
          <div>ID</div><div>Side</div><div>Price</div><div>Qty</div><div>Time</div>
        </div>
        {rows.map((o) => (
          <div key={String(o.id)} className="grid grid-cols-5 gap-2 border-t border-slate-200 py-2 text-slate-700 dark:border-white/5 dark:text-slate-200">
            <div>{String(o.id)}</div>
            <div className={o.side === "BUY" ? "text-emerald-300" : "text-rose-300"}>{o.side}</div>
            <div>{String(o.price)}</div>
            <div>{String(o.qty)}</div>
            <div>{new Date(o.createdAt).toLocaleTimeString()}</div>
          </div>
        ))}
        {!rows.length && <div className="pt-2 text-slate-500 dark:text-slate-400">No open orders</div>}
      </div>
    </div>
  );
}
