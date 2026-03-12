'use client';

import { useEffect, useState } from 'react';

type Order = {
  id: string;
  symbol: string;
  side: 'BUY'|'SELL';
  price: string;
  qty: string;
  filled: string;
  status: 'OPEN'|'FILLED'|'CANCELLED';
  createdAt: string;
};

type Trade = {
  id: string;
  symbol: string;
  price: string;
  qty: string;
  buyOrderId: string;
  sellOrderId: string;
  createdAt: string;
};

export default function OrdersPage() {
  const [open, setOpen] = useState<Order[]>([]);
  const [fills, setFills] = useState<Trade[]>([]);
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState<string|null>(null);

  async function load() {
    const [o, t] = await Promise.all([
      fetch('/api/my/orders', { cache: 'no-store' }).then(r=>r.json()),
      fetch('/api/my/trades', { cache: 'no-store' }).then(r=>r.json()),
    ]);
    setOpen((o.orders ?? []).filter((x:Order)=>x.status==='OPEN'));
    setFills(t.trades ?? []);
  }

  async function cancel(id: string) {
    setLoading(true); setMsg(null);
    const r = await fetch(`/api/orders/${id}/cancel`, { method:'POST' });
    const j = await r.json();
    setLoading(false);
    setMsg(j.ok ? `Cancelled #${id}` : `Cancel failed: ${j.error ?? 'unknown'}`);
    await load();
  }

  useEffect(()=>{ load(); }, []);

  return (
    <div className="max-w-6xl mx-auto px-6 py-8">
      <h1 className="text-3xl font-bold mb-6">Orders</h1>

      {msg && <div className="mb-4 rounded-lg border border-slate-700 bg-slate-900/40 px-4 py-3 text-sm">{msg}</div>}

      <section className="mb-10">
        <h2 className="text-xl font-semibold mb-3">Open Orders</h2>
        <div className="rounded-2xl border border-slate-800/60 bg-slate-900/30 overflow-hidden">
          <table className="w-full">
            <thead className="bg-slate-900/60">
              <tr className="text-left text-slate-300">
                <th className="px-4 py-2">ID</th>
                <th className="px-4 py-2">Symbol</th>
                <th className="px-4 py-2">Side</th>
                <th className="px-4 py-2">Price</th>
                <th className="px-4 py-2">Qty</th>
                <th className="px-4 py-2">Created</th>
                <th className="px-4 py-2"></th>
              </tr>
            </thead>
            <tbody>
              {open.length === 0 && (
                <tr><td className="px-4 py-4 text-slate-400" colSpan={7}>No open orders.</td></tr>
              )}
              {open.map(o => (
                <tr key={o.id} className="border-t border-slate-800">
                  <td className="px-4 py-2">{o.id}</td>
                  <td className="px-4 py-2">{o.symbol}</td>
                  <td className="px-4 py-2">{o.side}</td>
                  <td className="px-4 py-2">{o.price}</td>
                  <td className="px-4 py-2">{o.qty}</td>
                  <td className="px-4 py-2">{new Date(o.createdAt).toLocaleString()}</td>
                  <td className="px-4 py-2">
                    <button
                      onClick={()=>cancel(o.id)}
                      disabled={loading}
                      className="rounded-xl bg-rose-600/90 px-3 py-1 text-sm hover:bg-rose-600 disabled:opacity-60"
                    >
                      Cancel
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 className="text-xl font-semibold mb-3">Recent Fills</h2>
        <div className="rounded-2xl border border-slate-800/60 bg-slate-900/30 overflow-hidden">
          <table className="w-full">
            <thead className="bg-slate-900/60">
              <tr className="text-left text-slate-300">
                <th className="px-4 py-2">ID</th>
                <th className="px-4 py-2">Symbol</th>
                <th className="px-4 py-2">Price</th>
                <th className="px-4 py-2">Qty</th>
                <th className="px-4 py-2">When</th>
              </tr>
            </thead>
            <tbody>
              {fills.length === 0 && (
                <tr><td className="px-4 py-4 text-slate-400" colSpan={5}>No fills yet.</td></tr>
              )}
              {fills.map(f => (
                <tr key={f.id} className="border-top border-slate-800">
                  <td className="px-4 py-2">{f.id}</td>
                  <td className="px-4 py-2">{f.symbol}</td>
                  <td className="px-4 py-2">{f.price}</td>
                  <td className="px-4 py-2">{f.qty}</td>
                  <td className="px-4 py-2">{new Date(f.createdAt).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
