"use client";

import { useEffect, useState } from "react";

export default function PositionsPanel() {
  const [rows, setRows] = useState<any[]>([]);

  useEffect(() => {
    let alive = true;

    const load = () =>
      fetch(`/api/positions`, { cache: "no-store" })
        .then((r) => r.json())
        .then((j) => alive && setRows(j.balances ?? []))
        .catch(console.error);

    load();

    const t = setInterval(load, 2500);

    return () => {
      alive = false;
      clearInterval(t);
    };
  }, []);

  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-4">
      <div className="mb-2 text-sm text-slate-200">Positions (Spot Balances)</div>
      <div className="text-xs">
        <div className="grid grid-cols-2 gap-2 pb-2 text-slate-400">
          <div>Asset</div>
          <div className="text-right">Amount</div>
        </div>

        {rows.map((b) => (
          <div key={String(b.asset)} className="grid grid-cols-2 gap-2 border-t border-white/5 py-2 text-slate-200">
            <div>{b.asset}</div>
            <div className="text-right">{String(b.amount)}</div>
          </div>
        ))}

        {!rows.length && <div className="pt-2 text-slate-400">No balances</div>}
      </div>
    </div>
  );
}
