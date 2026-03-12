"use client";

import React, { useEffect, useMemo, useState } from "react";

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

function Chip({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center rounded-full border border-slate-200 bg-white px-2 py-0.5 text-xs text-slate-700 dark:border-slate-800/60 dark:bg-slate-950/40 dark:text-slate-300">
      {children}
    </span>
  );
}

function Btn({
  children,
  onClick,
  variant = "neutral",
  disabled,
  title,
}: {
  children: React.ReactNode;
  onClick?: () => void;
  variant?: "neutral" | "good" | "warn" | "danger";
  disabled?: boolean;
  title?: string;
}) {
  const base =
    "rounded-xl border px-3 py-2 text-sm font-medium transition disabled:opacity-50";
  const styles =
    variant === "good"
      ? "border-emerald-300 bg-emerald-50 text-emerald-900 hover:bg-emerald-100 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200 dark:hover:bg-emerald-500/15"
      : variant === "warn"
      ? "border-amber-300 bg-amber-50 text-amber-900 hover:bg-amber-100 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200 dark:hover:bg-amber-500/15"
      : variant === "danger"
      ? "border-rose-300 bg-rose-50 text-rose-900 hover:bg-rose-100 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200 dark:hover:bg-rose-500/15"
      : "border-slate-200 bg-white text-slate-900 hover:bg-slate-50 dark:border-slate-800/60 dark:bg-slate-950/30 dark:text-slate-100 dark:hover:bg-slate-900/40";

  return (
    <button className={`${base} ${styles}`} onClick={onClick} disabled={disabled} title={title}>
      {children}
    </button>
  );
}

export default function AdminDashboard() {
  const [health, setHealth] = useState<any>(null);
  const [btc, setBtc] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);

  // Small “admin state” placeholders (wire to real endpoints later)
  const [symbol, setSymbol] = useState("BTC-USD");
  const [mode, setMode] = useState<"PAPER" | "LIVE">("PAPER");
  const [depth, setDepth] = useState(20);

  useEffect(() => {
    let alive = true;

    async function load() {
      try {
        setErr(null);
        const [h, c] = await Promise.all([
          fetch("/api/health", { cache: "no-store" }).then((r) => r.json()).catch(() => null),
          fetch(`/api/candles/${encodeURIComponent("BTC-USD")}?period=1m&source=coinbase`, { cache: "no-store" }).then((r) =>
            r.json()
          ),
        ]);
        if (!alive) return;
        setHealth(h);
        setBtc(c);
      } catch (e: any) {
        if (!alive) return;
        setErr(String(e?.message ?? e));
      }
    }

    load();
    const t = setInterval(load, 5000);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, []);

  const last = useMemo(() => {
    const xs = btc?.candles ?? [];
    const x = xs[xs.length - 1];
    return x?.c ?? null;
  }, [btc]);

  return (
    <main className="min-h-screen bg-gradient-to-br from-white via-slate-50 to-indigo-50 text-slate-900 dark:from-slate-950 dark:via-slate-950 dark:to-indigo-950/20 dark:text-slate-100">
      <div className="mx-auto max-w-[1400px] space-y-4 px-6 py-6">
        {/* Header */}
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="text-2xl font-semibold">Admin Dashboard</div>
            <div className="text-sm text-slate-600 dark:text-slate-400">
              Ops • risk • compliance • audit • market controls • listings
            </div>
          </div>

          <div className="flex items-center gap-2">
            <a
              href={`/markets/${encodeURIComponent(symbol)}`}
              className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm hover:bg-slate-50 dark:border-slate-800/60 dark:bg-slate-950/30 dark:hover:bg-slate-900/40"
            >
              Back to Market
            </a>
          </div>
        </div>

        {err ? (
          <div className="rounded-xl border border-rose-300 bg-rose-50 p-3 text-sm text-rose-900 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200">
            {err}
          </div>
        ) : null}

        {/* Top row: status + ref feed + quick nav */}
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Panel title="System Health" right={<Chip>polls /api/health</Chip>}>
            <pre className="max-h-[260px] overflow-auto text-xs text-slate-700 dark:text-slate-300">
              {JSON.stringify(health, null, 2)}
            </pre>
          </Panel>

          <Panel title="Reference Feed (Coinbase)" right={<Chip>BTC-USD 1m</Chip>}>
            <div className="text-sm text-slate-700 dark:text-slate-300">
              Last close: <b className="text-slate-900 dark:text-slate-100">{last ?? "—"}</b>
            </div>
            <div className="mt-2 text-xs text-slate-600 dark:text-slate-400">
              If your internal book shows weird prices, reset/seed the demo market + re-seed ladders.
            </div>
          </Panel>

          <Panel title="Quick Links">
            <div className="flex flex-col gap-2 text-sm">
              <a className="underline underline-offset-2 text-slate-700 dark:text-slate-300" href="/portfolio">
                Portfolio
              </a>
              <a className="underline underline-offset-2 text-slate-700 dark:text-slate-300" href="/account">
                Account & KYC
              </a>
              <a className="underline underline-offset-2 text-slate-700 dark:text-slate-300" href={`/markets/${encodeURIComponent(symbol)}`}>
                Market: {symbol}
              </a>
            </div>
          </Panel>
        </div>

        {/* Investment-grade modules */}
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Panel title="Market Controls">
            <div className="grid grid-cols-1 gap-3 text-sm">
              <div className="grid grid-cols-3 gap-2">
                <div className="col-span-2">
                  <div className="text-xs text-slate-600 dark:text-slate-400">Symbol</div>
                  <input
                    className="mt-1 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 dark:border-slate-800/60 dark:bg-slate-950/30"
                    value={symbol}
                    onChange={(e) => setSymbol(e.target.value)}
                  />
                </div>
                <div>
                  <div className="text-xs text-slate-600 dark:text-slate-400">Mode</div>
                  <select
                    className="mt-1 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 dark:border-slate-800/60 dark:bg-slate-950/30"
                    value={mode}
                    onChange={(e) => setMode(e.target.value as any)}
                  >
                    <option value="PAPER">PAPER</option>
                    <option value="LIVE">LIVE</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2">
                <Btn variant="good" title="Wire to: POST /v1/admin/market/open (TBD)" disabled>
                  OPEN (TBD)
                </Btn>
                <Btn variant="warn" title="Wire to: POST /v1/admin/market/cancel-only (TBD)" disabled>
                  CANCEL_ONLY (TBD)
                </Btn>
                <Btn variant="danger" title="Wire to: POST /v1/admin/market/halt (TBD)" disabled>
                  HALT (TBD)
                </Btn>
                <Btn variant="neutral" title="Wire to: POST /v1/admin/market/cancel-all (TBD)" disabled>
                  CANCEL ALL (TBD)
                </Btn>
              </div>

              <div className="text-xs text-slate-600 dark:text-slate-400">
                **Investment-grade:** these controls must be RBAC-protected + fully audited.
              </div>
            </div>
          </Panel>

          <Panel title="KYC / AML (Ops Queue)">
            <ul className="space-y-2 text-sm text-slate-700 dark:text-slate-300">
              <li>• KYC status queue (PENDING → APPROVED/REJECTED)</li>
              <li>• Watchlist screening (sanctions/PEP/adverse media)</li>
              <li>• Ongoing monitoring (profile drift, risk score updates)</li>
              <li>• Case management + evidence attachments</li>
            </ul>
            <div className="mt-3 text-xs text-slate-600 dark:text-slate-400">
              UI now; later wire to endpoints like <code>/v1/admin/kyc</code>, <code>/v1/admin/cases</code>.
            </div>
          </Panel>

          <Panel title="Ledger, Audit & Forensics">
            <ul className="space-y-2 text-sm text-slate-700 dark:text-slate-300">
              <li>• Double-entry ledger (journal + immutable postings)</li>
              <li>• Daily reconciliation (cash/crypto, internal vs external)</li>
              <li>• Audit log (who/what/when) for every admin action</li>
              <li>• Forensic exports (orders, fills, balances, IP/device)</li>
            </ul>
            <div className="mt-3 text-xs text-slate-600 dark:text-slate-400">
              Minimum: append-only audit table + hash chain for tamper evidence.
            </div>
          </Panel>
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Panel title="Surveillance & Monitoring">
            <ul className="space-y-2 text-sm text-slate-700 dark:text-slate-300">
              <li>• Market abuse alerts (wash trades, spoofing, layering)</li>
              <li>• Risk limits (fat-finger, max notional, max orders/sec)</li>
              <li>• Latency & outage monitoring (SSE/WebSocket health)</li>
              <li>• Incident runbook + SLA targets</li>
            </ul>
          </Panel>

          <Panel title="Orders: Cancel / Stop / OCO (Roadmap)">
            <ul className="space-y-2 text-sm text-slate-700 dark:text-slate-300">
              <li>• STOP, STOP-LIMIT</li>
              <li>• OCO (one-cancels-other)</li>
              <li>• Reduce-only & post-only flags</li>
              <li>• Mass cancel (by user / symbol / side)</li>
            </ul>
            <div className="mt-3 text-xs text-slate-600 dark:text-slate-400">
              Your matcher can support this once orders have trigger conditions + a trigger engine.
            </div>
          </Panel>

          <Panel title="Listings: New Assets / RWA / Metals">
            <ul className="space-y-2 text-sm text-slate-700 dark:text-slate-300">
              <li>• Asset registry (precision, min size, fees, status)</li>
              <li>• Market creation workflow (symbol, tick, risk tier)</li>
              <li>• Custody integration checklist (hot/warm/cold)</li>
              <li>• Disclosures + product governance approvals</li>
            </ul>
          </Panel>
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Panel title="Reporting & Compliance">
            <ul className="space-y-2 text-sm text-slate-700 dark:text-slate-300">
              <li>• Trade reporting exports (CSV/Parquet)</li>
              <li>• Financial statements pack (PnL, balance sheet)</li>
              <li>• Regulatory reports (jurisdiction-specific)</li>
              <li>• Data retention / WORM storage policy</li>
            </ul>
          </Panel>

          <Panel title="Demo Ops: Seed / Reset (copy/paste)">
            <div className="text-xs text-slate-700 dark:text-slate-300">
              Use correct quoted table names:
            </div>
            <pre className="mt-2 overflow-auto rounded-xl border border-slate-200 bg-white p-3 text-xs text-slate-700 dark:border-slate-800/60 dark:bg-slate-950/30 dark:text-slate-300">
{`BEGIN;
DELETE FROM "Trade" WHERE symbol='BTC-USD' AND price < 1000;
DELETE FROM "Order" WHERE symbol='BTC-USD' AND price < 1000;
COMMIT;`}
            </pre>
          </Panel>

          <Panel title="Launch Checklist (investment-grade)">
            <ul className="space-y-2 text-sm text-slate-700 dark:text-slate-300">
              <li>✅ Candles + timeframe selector</li>
              <li>✅ Open Orders + Positions</li>
              <li>✅ Light/Dark theme consistency</li>
              <li>⬜ RBAC + admin-only routes</li>
              <li>⬜ Audit log + immutable ledger</li>
              <li>⬜ Market controls + mass cancel</li>
              <li>⬜ Surveillance + risk limits</li>
              <li>⬜ Reporting + reconciliation</li>
            </ul>
          </Panel>
        </div>
      </div>
    </main>
  );
}
