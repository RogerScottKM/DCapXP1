'use client';

import { useEffect, useMemo, useRef, useState } from 'react';

type Market = {
  symbol: string;
  baseAsset: string;
  quoteAsset: string;
  tickSize: string; // strings from API
  lotSize: string;
};

type Order = {
  id: string;
  symbol: string;
  side: 'BUY' | 'SELL';
  price: string;
  qty: string;
  filled?: string;
  status: 'OPEN' | 'FILLED' | 'CANCELLED';
  createdAt: string;
};

type Orderbook = { bids: Order[]; asks: Order[] };
type Trade = {
  id: string;
  symbol: string;
  price: string;
  qty: string;
  buyOrderId: string;
  sellOrderId: string;
  createdAt: string;
};

export default function DashboardPage() {
  const [markets, setMarkets] = useState<Market[]>([]);
  const [symbol, setSymbol] = useState<string>('');
  const [orderbook, setOrderbook] = useState<Orderbook>({ bids: [], asks: [] });
  const [trades, setTrades] = useState<Trade[]>([]);
  const [health, setHealth] = useState<'ok' | 'down' | 'checking'>('checking');

  // quick order state
  const [side, setSide] = useState<'BUY' | 'SELL'>('BUY');
  const [price, setPrice] = useState<string>('');
  const [qty, setQty] = useState<string>('');
  const [submitting, setSubmitting] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const esRef = useRef<EventSource | null>(null);

  // pull markets + health once
  useEffect(() => {
    (async () => {
      try {
        const h = await fetch('/api/health', { cache: 'no-store' });
        setHealth(h.ok ? 'ok' : 'down');
      } catch {
        setHealth('down');
      }
      const r = await fetch('/api/markets', { cache: 'no-store' });
      const j = await r.json();
      setMarkets(j.markets ?? []);
      if (!symbol && j.markets?.length) setSymbol(j.markets[0].symbol);
    })();
  }, []); // eslint-disable-line

  // when symbol changes, fetch snapshot + attach SSE
  useEffect(() => {
    if (!symbol) return;

    let cancelled = false;

    async function prime() {
      try {
        const [obR, trR] = await Promise.all([
          fetch(`/api/orderbook/${encodeURIComponent(symbol)}`, { cache: 'no-store' }),
          fetch(`/api/trades/${encodeURIComponent(symbol)}`, { cache: 'no-store' }),
        ]);
        const ob = await obR.json();
        const tr = await trR.json();
        if (!cancelled) {
          setOrderbook(ob);
          setTrades(tr.trades ?? []);
        }
      } catch {
        // ignore for now
      }
    }

    prime();

    if (esRef.current) {
      esRef.current.close();
      esRef.current = null;
    }
    const es = new EventSource(`/api/stream/${encodeURIComponent(symbol)}`);
    esRef.current = es;

    es.addEventListener('snapshot', (ev) => {
      try {
        const data = JSON.parse((ev as MessageEvent).data);
        setOrderbook(data.orderbook);
        setTrades(data.trades ?? []);
      } catch {}
    });
    es.addEventListener('orderbook', (ev) => {
      try {
        const data = JSON.parse((ev as MessageEvent).data);
        setOrderbook(data);
      } catch {}
    });

    es.onerror = () => {
      // auto-retry by EventSource; do nothing
    };

    return () => {
      cancelled = true;
      es.close();
      esRef.current = null;
    };
  }, [symbol]);

  const mkt = useMemo(() => markets.find(m => m.symbol === symbol), [markets, symbol]);
  const tickStep = useMemo(() => (mkt ? mkt.tickSize : '0.01'), [mkt]);
  const lotStep  = useMemo(() => (mkt ? mkt.lotSize  : '0.001'), [mkt]);

  const topBid = orderbook.bids[0]?.price ?? '-';
  const topAsk = orderbook.asks[0]?.price ?? '-';

  async function submitOrder(e: React.FormEvent) {
    e.preventDefault();
    if (!symbol) return;
    setSubmitting(true);
    setToast(null);
    try {
      const r = await fetch('/api/orders', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ symbol, side, price, qty }),
      });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || j.ok === false) {
        const msg = j.error ?? `Order failed (${r.status})`;
        setToast(`❌ ${msg}`);
      } else {
        setToast(`✅ ${side} ${qty} @ ${price} on ${symbol}`);
        setQty('');
      }
    } catch (err: any) {
      setToast(`❌ ${String(err?.message ?? err)}`);
    } finally {
      setSubmitting(false);
      setTimeout(() => setToast(null), 4500);
    }
  }

  return (
    <div className="max-w-6xl mx-auto px-6 py-8 space-y-8">
      <header className="flex flex-wrap items-center gap-4">
        <h1 className="text-2xl font-semibold tracking-tight">DCapX Dashboard</h1>
        <span
          className={`ml-2 rounded-full px-2 py-0.5 text-xs ${
            health === 'ok'
              ? 'bg-emerald-500/15 text-emerald-300 ring-1 ring-emerald-500/30'
              : health === 'checking'
              ? 'bg-amber-500/15 text-amber-300 ring-1 ring-amber-500/30'
              : 'bg-rose-500/15 text-rose-300 ring-1 ring-rose-500/30'
          }`}
        >
          API: {health}
        </span>

        <div className="ml-auto flex items-center gap-2">
          <label className="text-sm text-slate-400">Market</label>
          <select
            className="bg-slate-900 border border-slate-700 rounded-md px-3 py-2 text-sm"
            value={symbol}
            onChange={(e) => setSymbol(e.target.value)}
          >
            {markets.map((m) => (
              <option key={m.symbol} value={m.symbol}>
                {m.symbol}
              </option>
            ))}
          </select>
        </div>
      </header>

      {/* Top strip */}
      <section className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="rounded-2xl border border-slate-800 p-4 bg-slate-900/40">
          <div className="text-xs text-slate-400">Top Bid</div>
          <div className="text-2xl font-bold tabular-nums">{topBid}</div>
        </div>
        <div className="rounded-2xl border border-slate-800 p-4 bg-slate-900/40">
          <div className="text-xs text-slate-400">Top Ask</div>
          <div className="text-2xl font-bold tabular-nums">{topAsk}</div>
        </div>
        <div className="rounded-2xl border border-slate-800 p-4 bg-slate-900/40">
          <div className="text-xs text-slate-400">Tick / Lot</div>
          <div className="text-lg tabular-nums">
            {mkt?.tickSize ?? '-'} / {mkt?.lotSize ?? '-'}
          </div>
        </div>
      </section>

      {/* Book + Trades + Order form */}
      <section className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        {/* Orderbook */}
        <div className="xl:col-span-2 grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="rounded-2xl border border-slate-800 bg-slate-900/40">
            <div className="px-4 py-3 border-b border-slate-800 text-sm text-slate-300">Bids</div>
            <table className="w-full text-sm">
              <thead className="text-slate-400">
                <tr className="text-left">
                  <th className="px-4 py-2">Price</th>
                  <th className="px-4 py-2">Qty</th>
                  <th className="px-4 py-2">Time</th>
                </tr>
              </thead>
              <tbody className="tabular-nums">
                {orderbook.bids.map((b) => (
                  <tr key={b.id} className="odd:bg-slate-900/30">
                    <td className="px-4 py-2">{b.price}</td>
                    <td className="px-4 py-2">{b.qty}</td>
                    <td className="px-4 py-2">{formatTime(b.createdAt)}</td>
                  </tr>
                ))}
                {orderbook.bids.length === 0 && (
                  <tr><td className="px-4 py-3 text-slate-500" colSpan={3}>No bids</td></tr>
                )}
              </tbody>
            </table>
          </div>

          <div className="rounded-2xl border border-slate-800 bg-slate-900/40">
            <div className="px-4 py-3 border-b border-slate-800 text-sm text-slate-300">Asks</div>
            <table className="w-full text-sm">
              <thead className="text-slate-400">
                <tr className="text-left">
                  <th className="px-4 py-2">Price</th>
                  <th className="px-4 py-2">Qty</th>
                  <th className="px-4 py-2">Time</th>
                </tr>
              </thead>
              <tbody className="tabular-nums">
                {orderbook.asks.map((a) => (
                  <tr key={a.id} className="odd:bg-slate-900/30">
                    <td className="px-4 py-2">{a.price}</td>
                    <td className="px-4 py-2">{a.qty}</td>
                    <td className="px-4 py-2">{formatTime(a.createdAt)}</td>
                  </tr>
                ))}
                {orderbook.asks.length === 0 && (
                  <tr><td className="px-4 py-3 text-slate-500" colSpan={3}>No asks</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* Trades + Quick Order */}
        <div className="space-y-6">
          <div className="rounded-2xl border border-slate-800 bg-slate-900/40">
            <div className="px-4 py-3 border-b border-slate-800 text-sm text-slate-300">Recent Trades</div>
            <div className="max-h-72 overflow-auto">
              <table className="w-full text-sm">
                <thead className="text-slate-400 sticky top-0 bg-slate-900/80 backdrop-blur">
                  <tr className="text-left">
                    <th className="px-4 py-2">Time</th>
                    <th className="px-4 py-2">Price</th>
                    <th className="px-4 py-2">Qty</th>
                  </tr>
                </thead>
                <tbody className="tabular-nums">
                  {trades.map((t) => (
                    <tr key={t.id} className="odd:bg-slate-900/30">
                      <td className="px-4 py-2">{formatTime(t.createdAt)}</td>
                      <td className="px-4 py-2">{t.price}</td>
                      <td className="px-4 py-2">{t.qty}</td>
                    </tr>
                  ))}
                  {trades.length === 0 && (
                    <tr><td className="px-4 py-3 text-slate-500" colSpan={3}>No trades yet</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>

          <form onSubmit={submitOrder} className="rounded-2xl border border-slate-800 bg-slate-900/40 p-4 space-y-3">
            <div className="text-sm text-slate-300 mb-1">Quick Order</div>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setSide('BUY')}
                className={`px-3 py-1.5 rounded-md text-sm border ${
                  side === 'BUY'
                    ? 'bg-emerald-600/20 text-emerald-300 border-emerald-600/40'
                    : 'bg-slate-900 text-slate-300 border-slate-700'
                }`}
              >
                BUY
              </button>
              <button
                type="button"
                onClick={() => setSide('SELL')}
                className={`px-3 py-1.5 rounded-md text-sm border ${
                  side === 'SELL'
                    ? 'bg-rose-600/20 text-rose-300 border-rose-600/40'
                    : 'bg-slate-900 text-slate-300 border-slate-700'
                }`}
              >
                SELL
              </button>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <label className="text-sm">
                <span className="block text-slate-400 mb-1">Price</span>
                <input
                  inputMode="decimal"
                  step={tickStep}
                  value={price}
                  onChange={(e) => setPrice(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-700 rounded-md px-3 py-2"
                  placeholder={topAsk !== '-' ? topAsk : 'e.g. 95000'}
                  required
                />
              </label>
              <label className="text-sm">
                <span className="block text-slate-400 mb-1">Quantity</span>
                <input
                  inputMode="decimal"
                  step={lotStep}
                  value={qty}
                  onChange={(e) => setQty(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-700 rounded-md px-3 py-2"
                  placeholder="e.g. 0.01"
                  required
                />
              </label>
            </div>

            <button
              type="submit"
              disabled={submitting || !price || !qty}
              className="w-full mt-1 px-3 py-2 rounded-md bg-slate-100 text-slate-900 font-medium disabled:opacity-60"
            >
              {submitting ? 'Placing…' : `Place ${side}`}
            </button>

            {toast && <div className="text-xs text-slate-300">{toast}</div>}

            <div className="text-[11px] text-slate-500 pt-1">
              Orders are matched price–time priority; fills stream live into the book.
            </div>
          </form>
        </div>
      </section>
    </div>
  );
}

function formatTime(ts: string) {
  try {
    const d = new Date(ts);
    return d.toLocaleTimeString(undefined, { hour12: false });
  } catch {
    return ts;
  }
}
