"use client";

import { useEffect, useMemo, useState } from "react";

import CandlesPanel from "@/components/market/CandlesPanel";
import OpenOrdersPanel from "@/components/market/OpenOrdersPanel";
import PositionsPanel from "@/components/market/PositionsPanel";

type BookLevel = 2 | 3;
type Mode = "LIVE" | "PAPER";

type Control =
  | { mode: "OPEN"; reason?: string; updatedBy?: string; updatedAt?: string }
  | { mode: "HALT" | "CANCEL_ONLY"; reason?: string; updatedBy?: string; updatedAt?: string };

type Flags = {
  enableSSE: boolean;
  publicAllowL3: boolean;
  streamDefaultLevel: BookLevel;
  orderbookDefaultLevel: BookLevel;
};

type L2Row = { price: string; qty: string };
type L3Order = {
  id: string;
  symbol: string;
  side: "BUY" | "SELL";
  price: string;
  qty: string;
  status: string;
  createdAt: string;
  userId: string;
};

type Orderbook = { bids: L2Row[] | L3Order[]; asks: L2Row[] | L3Order[] };

type Trade = {
  id: string;
  symbol: string;
  price: string;
  qty: string;
  createdAt: string;
  buyOrderId: string;
  sellOrderId: string;
};

function Panel({
  title,
  right,
  children,
}: {
  title: string;
  right?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-slate-200/70 bg-white/80 text-slate-900 shadow-sm backdrop-blur-md dark:border-slate-800/60 dark:bg-slate-950/40 dark:text-slate-100">
      <div className="flex items-center justify-between border-b border-slate-200/70 px-4 py-3 dark:border-slate-800/60">
        <div className="text-sm font-semibold">{title}</div>
        {right ? <div className="text-xs text-slate-500 dark:text-slate-400">{right}</div> : null}
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}

export default function MarketClient({ symbol }: { symbol: string }) {
  const [mode, setMode] = useState<Mode>("LIVE");
  const [depth, setDepth] = useState(25);
  const [level, setLevel] = useState<BookLevel>(2);

  const [orderbook, setOrderbook] = useState<Orderbook | null>(null);
  const [trades, setTrades] = useState<Trade[]>([]);
  const [control, setControl] = useState<Control | null>(null);
  const [flags, setFlags] = useState<Flags | null>(null);

  const [status, setStatus] = useState<"connecting" | "live" | "error">("connecting");
  const [lastError, setLastError] = useState<string | null>(null);

  const input =
    "rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-900 dark:border-slate-800/60 dark:bg-slate-950/30 dark:text-slate-100";

  // IMPORTANT: hit API SSE directly (nginx routes /v1/stream -> :4010 with SSE rules)
  const streamUrl = useMemo(() => {
    const qs = new URLSearchParams();
    qs.set("depth", String(depth));
    qs.set("level", String(level));
    // If your SSE supports mode, keep this; if not, it will usually be ignored safely.
    qs.set("mode", mode);
    return `/v1/stream/${encodeURIComponent(symbol)}?${qs.toString()}`;
  }, [symbol, depth, level, mode]);

  useEffect(() => {
    setStatus("connecting");
    setLastError(null);

    const es = new EventSource(streamUrl);

    const onJson = (cb: (data: any) => void) => (ev: MessageEvent) => {
      try {
        cb(JSON.parse(ev.data));
      } catch (e: any) {
        setLastError(`Bad SSE JSON: ${String(e?.message ?? e)}`);
        setStatus("error");
      }
    };

    es.addEventListener(
      "snapshot",
      onJson((d) => {
        setOrderbook(d.orderbook);
        setTrades(d.trades ?? []);
        setControl(d.control ?? null);
        setFlags(d.flags ?? null);
        setStatus("live");
      })
    );

    es.addEventListener(
      "orderbook",
      onJson((d) => {
        setOrderbook(d.orderbook);
        if (d.control) setControl(d.control);
      })
    );

    es.addEventListener(
      "trades",
      onJson((d) => {
        setTrades(d.trades ?? []);
      })
    );

    es.addEventListener(
      "mode",
      onJson((d) => {
        if (d.control) setControl(d.control);
      })
    );

    es.addEventListener(
      "flags",
      onJson((d) => {
        if (d.flags) setFlags(d.flags);
      })
    );

    es.addEventListener(
      "error",
      onJson((d) => {
        setLastError(d?.error ?? "Stream error");
        setStatus("error");
      })
    );

    es.onerror = async () => {
      setStatus("error");
      try {
        const r = await fetch(streamUrl, { cache: "no-store" });
        const ct = r.headers.get("content-type") ?? "";
        if (ct.includes("application/json")) {
          const j = await r.json();
          setLastError(j?.error ?? `${r.status} ${r.statusText}`);
          if (j?.flags) setFlags(j.flags);
        } else {
          setLastError(`${r.status} ${r.statusText}`);
        }
      } catch {
        setLastError("Unable to connect to stream");
      }
      es.close();
    };

    return () => es.close();
  }, [streamUrl]);

  const canUseL3 = flags?.publicAllowL3 ?? false;

  return (
    <main className="min-h-screen bg-gradient-to-br from-white via-slate-50 to-indigo-50 text-slate-900 dark:from-slate-950 dark:via-slate-950 dark:to-indigo-950/20 dark:text-slate-100">
      <div className="mx-auto max-w-[1400px] space-y-4 px-6 py-6">
        {/* Header + controls */}
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <div className="text-2xl font-semibold">{symbol}</div>
            <div className="text-sm text-slate-600 dark:text-slate-400">
              Status: {status}
              {lastError ? ` • ${lastError}` : ""} • Mode: {mode}
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <label className="text-sm text-slate-600 dark:text-slate-400">Mode</label>
            <select
              className={input}
              value={mode}
              onChange={(e) => setMode((e.target.value as Mode) || "LIVE")}
            >
              <option value="LIVE">LIVE</option>
              <option value="PAPER">PAPER</option>
            </select>

            <label className="text-sm text-slate-600 dark:text-slate-400">Depth</label>
            <input
              className={`${input} w-24`}
              type="number"
              min={1}
              max={500}
              value={depth}
              onChange={(e) => setDepth(Number(e.target.value || 25))}
            />

            <label className="text-sm text-slate-600 dark:text-slate-400">Level</label>
            <select
              className={input}
              value={level}
              onChange={(e) => setLevel((Number(e.target.value) as BookLevel) || 2)}
            >
              <option value={2}>L2</option>
              <option value={3} disabled={!canUseL3}>
                L3{!canUseL3 ? " (admin only)" : ""}
              </option>
            </select>
          </div>
        </div>

        {/* Control banner */}
        {control && control.mode !== "OPEN" ? (
          <div className="rounded-2xl border border-amber-300 bg-amber-50 p-4 text-amber-900 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200">
            <div className="font-semibold">⚠️ {control.mode}</div>
            <div className="text-sm opacity-90">
              {control.reason ?? "no reason"} • {control.updatedBy ?? "?"} • {control.updatedAt ?? "?"}
            </div>
          </div>
        ) : null}

        {/* Layout */}
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          {/* Left: Candles + Open Orders + Positions */}
          <div className="lg:col-span-2 space-y-4">
            <CandlesPanel symbol={symbol} mode={mode} />
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
              <OpenOrdersPanel symbol={symbol} />
              <PositionsPanel />
            </div>
          </div>

          {/* Right: Debug panels */}
          <div className="lg:col-span-1 space-y-4">
            <Panel title="Orderbook (debug)">
              {!orderbook ? (
                <div className="text-sm text-slate-600 dark:text-slate-400">Waiting…</div>
              ) : (
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <div className="mb-1 text-sm font-semibold">Bids</div>
                    <pre className="max-h-[360px] overflow-auto text-xs text-slate-700 dark:text-slate-300">
                      {JSON.stringify((orderbook as any).bids, null, 2)}
                    </pre>
                  </div>
                  <div>
                    <div className="mb-1 text-sm font-semibold">Asks</div>
                    <pre className="max-h-[360px] overflow-auto text-xs text-slate-700 dark:text-slate-300">
                      {JSON.stringify((orderbook as any).asks, null, 2)}
                    </pre>
                  </div>
                </div>
              )}
            </Panel>

            <Panel title="Trades (debug)">
              <pre className="max-h-[420px] overflow-auto text-xs text-slate-700 dark:text-slate-300">
                {JSON.stringify(trades, null, 2)}
              </pre>
            </Panel>

            {flags ? (
              <Panel title="Flags (debug)">
                <pre className="text-xs text-slate-700 dark:text-slate-300">{JSON.stringify(flags, null, 2)}</pre>
              </Panel>
            ) : null}

            <div className="text-xs text-slate-600 dark:text-slate-400">
              Next: replace debug panels with your styled Orderbook/Trades + Order Ticket (like MarketScreen).
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}
