'use client';

import { useEffect, useMemo, useRef, useState } from 'react';

type Side = 'BUY' | 'SELL';
type OrderRow = {
  id: string; symbol: string; side: Side;
  price: string; qty: string;
  status: 'OPEN' | 'FILLED' | 'CANCELLED';
  createdAt: string;
};
type Orderbook = { bids: OrderRow[]; asks: OrderRow[] };
type Trade = {
  id: string; symbol: string; price: string; qty: string;
  buyOrderId: string; sellOrderId: string; createdAt: string;
};
type Market = { symbol: string; baseAsset: string; quoteAsset: string; tickSize: string; lotSize: string; createdAt: string };

function fmt(n: string | number) {
  const x = typeof n === 'string' ? Number(n) : n;
  return Number.isFinite(x) ? x.toLocaleString() : String(n);
}

export default function ExchangePage() {
  const [markets, setMarkets] = useState<string[]>([]);
  const [symbol, setSymbol] = useState('BTC-USD');
  const [orderbook, setOrderbook] = useState<Orderbook>({ bids: [], asks: [] });
  const [trades, setTrades] = useState<Trade[]>([]);
  const [side, setSide] = useState<Side>('BUY');
  const [price, setPrice] = useState('');
  const [qty, setQty] = useState('');
  const [busy, setBusy] = useState(false);
  const esRef = useRef<EventSource | null>(null);

  // load markets from API, select first if current not available
  useEffect(() => {
    let aborted = false;
    (async () => {
      const r = await fetch('/api/markets', { cache: 'no-store' });
      const j = await r.json() as { markets: Market[] };
      if (aborted) return;
      const list = (j.markets ?? []).map(m => m.symbol);
      setMarkets(list);
      if (list.length && !list.includes(symbol)) setSymbol(list[0]);
    })();
    return () => { aborted = true; };
  }, []);

  // bootstrap ob + trades for current symbol
  useEffect(() => {
    if (!symbol) return;
    let aborted = false;
    (async () => {
      const [ob, tr] = await Promise.all([
        fetch(`/api/orderbook/${symbol}`, { cache: 'no-store' }).then(r => r.json()),
        fetch(`/api/trades/${symbol}`,     { cache: 'no-store' }).then(r => r.json()),
      ]);
      if (aborted) return;
      setOrderbook(ob);
      setTrades(tr.trades ?? []);
    })();
    return () => { aborted = true; };
  }, [symbol]);

  // live SSE for the symbol
  useEffect(() => {
    if (!symbol) return;
    esRef.current?.close();
    const es = new EventSource(`/api/stream/${symbol}`);
    es.addEventListener('snapshot', (e: MessageEvent) => {
      try {
        const data = JSON.parse(e.data);
        setOrderbook(data.orderbook);
        setTrades(data.trades ?? []);
      } catch {}
    });
    es.addEventListener('orderbook', (e: MessageEvent) => {
      try {
        const data = JSON.parse(e.data);
        setOrderbook(data);
      } catch {}
    });
    esRef.current = es;
    return () => es.close();
  }, [symbol]);

  const bestBid = useMemo(() => orderbook.bids[0]?.price ?? '', [orderbook]);
  const bestAsk = useMemo(() => orderbook.asks[0]?.price ?? '', [orderbook]);

  async function placeOrder(e: React.FormEvent) {
    e.preventDefault();
    if (!symbol) return;
    setBusy(true);
    try {
      const body = { symbol, side, price, qty };
      const r = await fetch('/api/orders', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
      });
      const j = await r.json();
      if (!r.ok || !j.ok) throw new Error(j?.error ?? `HTTP ${r.status}`);
      setQty('');
    } catch (err: any) {
      alert(`Order failed: ${err?.message ?? err}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="max-w-6xl mx-auto px-4 py-8 space-y-8">
      <header className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold">DCapital Exchange (MVP)</h1>
        <div className="flex items-center gap-3">
          <select
            className="border rounded px-3 py-2"
            value={symbol}
            onChange={(e) => setSymbol(e.target.value)}
          >
            {markets.map(s => <option key={s} value={s}>{s}</option>)}
            {markets.length === 0 && <option>Loading…</option>}
          </select>
          <a href="/" className="text-sm underline">Home</a>
        </div>
      </header>

      <form onSubmit={placeOrder} className="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
        <div className="md:col-span-1">
          <label className="block text-sm mb-1">Side</label>
          <div className="flex gap-2">
            <button type="button" onClick={() => setSide('BUY')}
              className={`px-3 py-2 rounded border ${side === 'BUY' ? 'bg-green-600 text-white' : ''}`}>Buy</button>
            <button type="button" onClick={() => setSide('SELL')}
              className={`px-3 py-2 rounded border ${side === 'SELL' ? 'bg-red-600 text-white' : ''}`}>Sell</button>
          </div>
        </div>

        <div>
          <label className="block text-sm mb-1">Price</label>
          <div className="flex gap-2">
            <input className="w-full border rounded px-3 py-2" inputMode="decimal"
              value={price} onChange={(e) => setPrice(e.target.value)} placeholder="e.g. 95000" required />
            <button type="button" className="px-2 border rounded" onClick={() => setPrice(bestBid || price)}>← Bid</button>
            <button type="button" className="px-2 border rounded" onClick={() => setPrice(bestAsk || price)}>Ask →</button>
          </div>
        </div>

        <div>
          <label className="block text-sm mb-1">Quantity</label>
          <input className="w-full border rounded px-3 py-2" inputMode="decimal"
            value={qty} onChange={(e) => setQty(e.target.value)} placeholder="e.g. 0.05" required />
        </div>

        <div className="md:col-span-2">
          <button type="submit" disabled={busy}
            className="w-full md:w-auto px-4 py-3 rounded bg-blue-600 text-white disabled:opacity-50">
            {busy ? 'Placing…' : `Place ${side}`}
          </button>
          <div className="text-xs text-gray-500 mt-2">
            Matching is price–time priority on the server. Book + trades stream live.
          </div>
        </div>
      </form>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div>
          <h2 className="font-medium mb-2">Bids</h2>
          <div className="border rounded overflow-auto max-h-[420px]">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-gray-50"><tr>
                <th className="text-left px-3 py-2">Price</th>
                <th className="text-left px-3 py-2">Qty</th>
                <th className="text-left px-3 py-2">Time</th>
              </tr></thead>
              <tbody>
                {orderbook.bids.map((b) => (
                  <tr key={b.id} className="hover:bg-green-50">
                    <td className="px-3 py-1 font-medium">{fmt(b.price)}</td>
                    <td className="px-3 py-1">{fmt(b.qty)}</td>
                    <td className="px-3 py-1">{new Date(b.createdAt).toLocaleTimeString()}</td>
                  </tr>
                ))}
                {orderbook.bids.length === 0 && <tr><td className="px-3 py-2 text-gray-500" colSpan={3}>No bids</td></tr>}
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <h2 className="font-medium mb-2">Asks</h2>
          <div className="border rounded overflow-auto max-h-[420px]">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-gray-50"><tr>
                <th className="text-left px-3 py-2">Price</th>
                <th className="text-left px-3 py-2">Qty</th>
                <th className="text-left px-3 py-2">Time</th>
              </tr></thead>
              <tbody>
                {orderbook.asks.map((a) => (
                  <tr key={a.id} className="hover:bg-red-50">
                    <td className="px-3 py-1 font-medium">{fmt(a.price)}</td>
                    <td className="px-3 py-1">{fmt(a.qty)}</td>
                    <td className="px-3 py-1">{new Date(a.createdAt).toLocaleTimeString()}</td>
                  </tr>
                ))}
                {orderbook.asks.length === 0 && <tr><td className="px-3 py-2 text-gray-500" colSpan={3}>No asks</td></tr>}
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <h2 className="font-medium mb-2">Recent Trades</h2>
          <div className="border rounded overflow-auto max-h-[420px]">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-gray-50"><tr>
                <th className="text-left px-3 py-2">Price</th>
                <th className="text-left px-3 py-2">Qty</th>
                <th className="text-left px-3 py-2">Time</th>
              </tr></thead>
              <tbody>
                {trades.map((t) => (
                  <tr key={t.id}>
                    <td className="px-3 py-1">{fmt(t.price)}</td>
                    <td className="px-3 py-1">{fmt(t.qty)}</td>
                    <td className="px-3 py-1">{new Date(t.createdAt).toLocaleTimeString()}</td>
                  </tr>
                ))}
                {trades.length === 0 && <tr><td className="px-3 py-2 text-gray-500" colSpan={3}>No trades</td></tr>}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div className="text-xs text-gray-500">Add more markets in Postgres; they’ll appear in the dropdown.</div>
    </div>
  );
}
