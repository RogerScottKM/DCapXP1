import Link from "next/link";

function Card({
  title,
  right,
  children,
}: {
  title: string;
  right?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-slate-200/70 bg-white/70 p-5 shadow-sm backdrop-blur dark:border-white/10 dark:bg-white/5 dark:shadow-none">
      <div className="mb-3 flex items-center justify-between">
        <div className="text-sm font-medium text-slate-700 dark:text-slate-200">{title}</div>
        {right}
      </div>
      {children}
    </div>
  );
}

function Stat({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="rounded-2xl border border-slate-200/70 bg-white/70 p-4 shadow-sm backdrop-blur dark:border-white/10 dark:bg-white/5 dark:shadow-none">
      <div className="text-xs text-slate-500 dark:text-slate-400">{label}</div>
      <div className="mt-1 text-xl font-semibold tracking-tight text-slate-900 dark:text-white">
        {value}
      </div>
      {sub ? <div className="mt-1 text-xs text-slate-500 dark:text-slate-400">{sub}</div> : null}
    </div>
  );
}

export default function DashboardPage() {
  // TODO: replace with real API (portfolio summary + aptivio + bnpl + skills)
  const demo = {
    user: "demo user",
    plan: "Newbie",
    netWorth: "$1,585,430",
    pnl24h: "+$3,514 ( +0.29% )",
    cash: "$350,000",
    bnplExposure: "$12,400",
    aptivioScore: 742,
    aptivioStatus: "GREEN",
    skillLevel: "Intermediate",
    nextAction: "Enable Autopilot after API keys + RBAC",
    watchlist: [
      { sym: "BTC-USD", last: "66,832", chg: "+0.61%" },
      { sym: "ETH-USD", last: "3,512", chg: "-0.12%" },
      { sym: "SOL-USD", last: "148.2", chg: "+1.04%" },
    ],
    insights: [
      "Risk guardrails: fat-finger bands ON • slippage cap applies to MARKET",
      "Aptivio Nexus: connect 1 bank + 1 card to unlock ‘bankable’ profile",
      "Skill assessment: 2 modules pending (Position sizing, Limit vs Market)",
    ],
  };

  return (
    <div className="mx-auto max-w-6xl px-6 py-10">
      <div className="mb-8 flex items-end justify-between gap-4">
        <div>
          <div className="text-xs text-slate-500 dark:text-slate-400">
            Plan: <span className="font-medium text-slate-700 dark:text-slate-200">{demo.plan}</span>
          </div>
          <h1 className="mt-1 text-3xl font-semibold tracking-tight text-slate-900 dark:text-white">
            Dashboard <span className="ml-2 text-sm font-normal text-slate-500 dark:text-slate-400">{demo.user}</span>
          </h1>
          <div className="mt-2 text-sm text-slate-500 dark:text-slate-400">
            Investment-grade overview • risk, performance, and agent readiness.
          </div>
        </div>

        <div className="flex gap-2">
          <Link
            href="/exchange/BTC-USD"
            className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm text-slate-800 shadow-sm hover:bg-slate-50 dark:border-white/10 dark:bg-white/5 dark:text-slate-200 dark:hover:bg-white/10"
          >
            Go to Exchange
          </Link>
          <Link
            href="/portfolio"
            className="rounded-xl bg-emerald-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-emerald-500"
          >
            View Portfolio
          </Link>
        </div>
      </div>

      {/* KPI row */}
      <div className="grid gap-4 md:grid-cols-4">
        <Stat label="Net worth" value={demo.netWorth} sub="All accounts + positions" />
        <Stat label="Cash & stables" value={demo.cash} sub="Available buying power" />
        <Stat label="P&L (24h)" value={demo.pnl24h} sub="Estimated mark-to-market" />
        <Stat
          label="Aptivio Score"
          value={`${demo.aptivioScore}`}
          sub={`Status: ${demo.aptivioStatus} • Skill: ${demo.skillLevel}`}
        />
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-3">
        {/* Performance */}
        <div className="lg:col-span-2">
          <Card
            title="Performance (MVP)"
            right={<span className="text-xs text-slate-500 dark:text-slate-400">YTD • demo</span>}
          >
            <div className="h-52 rounded-xl border border-slate-200/70 bg-white/60 dark:border-white/10 dark:bg-white/5" />
            <div className="mt-3 grid gap-3 md:grid-cols-3">
              <div className="rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600 dark:bg-white/5 dark:text-slate-300">
                Exposure: <span className="font-medium">Spot</span> (paper)
              </div>
              <div className="rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600 dark:bg-white/5 dark:text-slate-300">
                Risk mode: <span className="font-medium">Guardrails ON</span>
              </div>
              <div className="rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600 dark:bg-white/5 dark:text-slate-300">
                Autopilot: <span className="font-medium">OFF</span>
              </div>
            </div>
          </Card>
        </div>

        {/* Agent readiness */}
        <Card title="Agent Readiness">
          <div className="text-sm text-slate-700 dark:text-slate-200">
            Next action
          </div>
          <div className="mt-1 text-sm text-slate-500 dark:text-slate-400">
            {demo.nextAction}
          </div>

          <div className="mt-4">
            <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400">
              <span>BNPL exposure</span>
              <span className="text-slate-700 dark:text-slate-200">{demo.bnplExposure}</span>
            </div>
            <div className="mt-2 h-2 w-full rounded-full bg-slate-200 dark:bg-white/10">
              <div className="h-2 w-[32%] rounded-full bg-amber-500" />
            </div>
            <div className="mt-2 text-xs text-slate-500 dark:text-slate-400">
              Target: keep &lt; 35% of monthly income.
            </div>
          </div>

          <div className="mt-4 border-t border-slate-200/70 pt-4 dark:border-white/10">
            <div className="text-sm text-slate-700 dark:text-slate-200">Aptivio Nexus</div>
            <div className="mt-1 text-xs text-slate-500 dark:text-slate-400">
              Connect data sources to unlock bankable scoring + personalized plan.
            </div>
            <div className="mt-3 flex gap-2">
              <button className="rounded-xl bg-white px-3 py-2 text-xs text-slate-800 shadow-sm hover:bg-slate-50 dark:bg-white/5 dark:text-slate-200 dark:hover:bg-white/10">
                Connect Bank (demo)
              </button>
              <button className="rounded-xl bg-white px-3 py-2 text-xs text-slate-800 shadow-sm hover:bg-slate-50 dark:bg-white/5 dark:text-slate-200 dark:hover:bg-white/10">
                Connect Card (demo)
              </button>
            </div>
          </div>
        </Card>
      </div>

      {/* Lower row */}
      <div className="mt-6 grid gap-4 lg:grid-cols-3">
        <Card title="Watchlist">
          <div className="divide-y divide-slate-200/70 dark:divide-white/10">
            {demo.watchlist.map((x) => (
              <div key={x.sym} className="flex items-center justify-between py-3 text-sm">
                <div className="text-slate-800 dark:text-slate-200">{x.sym}</div>
                <div className="flex items-center gap-3">
                  <div className="text-slate-500 dark:text-slate-400">{x.last}</div>
                  <div className="rounded-lg bg-emerald-500/10 px-2 py-1 text-xs text-emerald-600 dark:text-emerald-300">
                    {x.chg}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>

        <Card title="Skill Assessment">
          <div className="text-sm text-slate-700 dark:text-slate-200">Level: {demo.skillLevel}</div>
          <div className="mt-2 text-xs text-slate-500 dark:text-slate-400">
            You’ll see smarter guardrails + larger limits as skills improve.
          </div>
          <div className="mt-4 space-y-2">
            <div className="rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600 dark:bg-white/5 dark:text-slate-300">
              ✅ Candlesticks + timeframe selector
            </div>
            <div className="rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600 dark:bg-white/5 dark:text-slate-300">
              ⏳ Position sizing module
            </div>
            <div className="rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600 dark:bg-white/5 dark:text-slate-300">
              ⏳ Limit vs Market mastery
            </div>
          </div>
        </Card>

        <Card title="Insights">
          <ul className="space-y-3 text-sm text-slate-600 dark:text-slate-300">
            {demo.insights.map((x, i) => (
              <li key={i} className="rounded-xl bg-slate-50 px-3 py-2 dark:bg-white/5">
                {x}
              </li>
            ))}
          </ul>
        </Card>
      </div>
    </div>
  );
}
