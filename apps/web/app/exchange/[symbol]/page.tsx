'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import Candles from '@/components/Candles';

type Order = {
  id: string;
  symbol: string;
  side: 'BUY' | 'SELL';
  price: string;
  qty: string;
  status: 'OPEN' | 'FILLED' | 'CANCELLED';
  createdAt: string;
};

type Orderbook = {
  bids: Order[];
  asks: Order[];
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

export default function ExchangePage({ params }: { params: { symbol: string } }) {
  const symbol = useMemo(
    () => decodeURIComponent(params.symbol).toUpperCase(),
    [params.symbol]
  );

  const [book, setBook] = useState<Orderbook>({ bids: [], asks: [] });
  const [trades, setTrades] = useState<Trade[]>([]);
  const [loading, setLoading] = useState(true);

  // Initial fetch + SSE live updates
  useEffect(() => {
    let closed = false;

    async function load() {
      setLoading(true);
      try {
        const [bRes, tRes] = await Promise.all([
          fetch(`/api/orderbook/${encodeURIComponent(symbol)}`, { cache: 'no-store' }),
          fetch(`/api/trades/${encodeURIComponent(symbol)}`, { cache: 'no-store' }),
        ]);
        const bJson = (await bRes.json()) as Orderbook;
        const tJson = (await tRes.json()) as { trades: Trade[] };
        if (!closed) {
          setBook(bJson);
          setTrades(tJson.trades ?? []);
        }
      } finally {
        if (!closed) setLoading(false);
      }
    }

    // SSE stream
    const es = new EventSource(`/api/stream/${encodeURIComponent(symbol)}`);
    es.addEventListener('snapshot', (e) => {
      const data = JSON.parse((e as MessageEvent).data) as {
        orderbook: Orderbook;
        trades: Trade[];
      };
      setBook(data.orderbook);
      setTrades(data.trades ?? []);
    });
    es.addEventListener('orderbook', (e) => {
      const data = JSON.parse((e as MessageEvent).data) as Orderbook;
      setBook(data);
    });
    es.addEventListener('trades', (e) => {
      const data = JSON.parse((e as MessageEvent).data) as Trade[];
      // Put newest first
      setTrades(data);
    });

    load();

    return () => {
      closed = true;
      es.close();
    };
  }, [symbol]);

  return (
    <main className="max-w-6xl mx-auto px-6 py-8">
      <div className="flex items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold">
          Exchange <span className="text-slate-400">{symbol}</span>
        </h1>
        <nav className="text-sm text-slate-300 flex items-center gap-4">
          <Link className="hover:text-white" href="/dashboard">Dashboard</Link>
          <Link className="hover:text-white" href="/portfolio">Portfolio</Link>
        </nav>
      </div>

      {/* Quick pair switches (optional) */}
      <div className="mt-3 text-sm text-slate-400 flex items-center gap-3">
        <span>Pairs:</span>
        <Link className="hover:text-white underline-offset-4 hover:underline" href="/exchange/BTC-USD">BTC-USD</Link>
        <Link className="hover:text-white underline-offset-4 hover:underline" href="/exchange/ETH-USD">ETH-USD</Link>
      </div>

      {/* PRICE CHART */}
      <section className="mt-6">
        <h2 className="mb-3 text-sm font-medium text-slate-300">Price chart</h2>
        <div className="rounded-2xl border border-slate-800/60 bg-slate-900/40 p-3 w-full">
          <Candles symbol={symbol} height={380} intervalMinutes={1} />
        </div>
      </section>

      {/* BOOK + TRADES */}
      <section className="mt-6 grid gap-6 md:grid-cols-2">
        {/* Orderbook */}
        <div className="rounded-2xl border border-slate-800/60 bg-slate-900/40">
          <div className="px-4 py-3 border-b border-slate-800/60 flex items-center justify-between">
            <h3 className="text-sm font-medium text-slate-300">Orderbook</h3>
            {loading && <span className="text-xs text-slate-500">loading…</span>}
          </div>
          <div className="grid grid-cols-2 gap-0">
            <div className="p-3">
              <div className="text-xs uppercase tracking-wide text-slate-400 mb-2">Bids</div>
              <table className="w-full text-sm">
                <thead className="text-slate-400">
                  <tr>
                    <th className="text-left font-medium py-1">Price</th>
                    <th className="text-right font-medium py-1">Qty</th>
                  </tr>
                </thead>
                <tbody>
                  {book.bids.map((b) => (
                    <tr key={b.id} className="border-t border-slate-800/60">
                      <td className="py-1 pr-2 text-emerald-400">{b.price}</td>
                      <td className="py-1 pl-2 text-right">{b.qty}</td>
                    </tr>
                  ))}
                  {book.bids.length === 0 && (
                    <tr><td colSpan={2} className="py-2 text-slate-500">No bids</td></tr>
                  )}
                </tbody>
              </table>
            </div>
            <div className="p-3">
              <div className="text-xs uppercase tracking-wide text-slate-400 mb-2">Asks</div>
              <table className="w-full text-sm">
                <thead className="text-slate-400">
                  <tr>
                    <th className="text-left font-medium py-1">Price</th>
                    <th className="text-right font-medium py-1">Qty</th>
                  </tr>
                </thead>
                <tbody>
                  {book.asks.map((a) => (
                    <tr key={a.id} className="border-t border-slate-800/60">
                      <td className="py-1 pr-2 text-rose-400">{a.price}</td>
                      <td className="py-1 pl-2 text-right">{a.qty}</td>
                    </tr>
                  ))}
                  {book.asks.length === 0 && (
                    <tr><td colSpan={2} className="py-2 text-slate-500">No asks</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {/* Recent trades */}
        <div className="rounded-2xl border border-slate-800/60 bg-slate-900/40">
          <div className="px-4 py-3 border-b border-slate-800/60 flex items-center justify-between">
            <h3 className="text-sm font-medium text-slate-300">Recent trades</h3>
            <span className="text-xs text-slate-500">{trades.length}</span>
          </div>
          <div className="p-3">
            <table className="w-full text-sm">
              <thead className="text-slate-400">
                <tr>
                  <th className="text-left font-medium py-1">Time (UTC)</th>
                  <th className="text-right font-medium py-1">Price</th>
                  <th className="text-right font-medium py-1">Qty</th>
                </tr>
              </thead>
              <tbody>
                {trades.map((t) => (
                  <tr key={t.id} className="border-t border-slate-800/60">
                    <td className="py-1 pr-2">{new Date(t.createdAt).toISOString().split('T')[1]?.slice(0, 8)}</td>
                    <td className="py-1 pl-2 text-right">{t.price}</td>
                    <td className="py-1 pl-2 text-right">{t.qty}</td>
                  </tr>
                ))}
                {trades.length === 0 && (
                  <tr><td colSpan={3} className="py-2 text-slate-500">No trades yet</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </main>
  );
}
