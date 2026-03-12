function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-slate-200/70 bg-white/70 p-5 shadow-sm backdrop-blur dark:border-white/10 dark:bg-white/5 dark:shadow-none">
      <div className="mb-3 text-sm font-medium text-slate-700 dark:text-slate-200">{title}</div>
      {children}
    </div>
  );
}

export default function PortfolioPage() {
  // TODO: wire to real balances + pricing (Coinbase source)
  const demo = {
    user: "demo user",
    balances: [
      { asset: "USD", amount: 350000, value: 350000, change24h: "+0.00%" },
      { asset: "BTC", amount: 15, value: 1002480, change24h: "+0.61%" },
      { asset: "ETH", amount: 120, value: 421440, change24h: "-0.12%" },
    ],
    aptivioScore: 742,
    aptivioStatus: "GREEN",
    bnpl: { exposure: 12400, nextPayment: 620, dueInDays: 9 },
    plan: "Personalised Financial Plan (MVP)",
  };

  const total = demo.balances.reduce((s, x) => s + x.value, 0);

  return (
    <div className="mx-auto max-w-6xl px-6 py-10">
      <div className="mb-8">
        <h1 className="text-3xl font-semibold tracking-tight text-slate-900 dark:text-white">
          Portfolio <span className="ml-2 text-sm font-normal text-slate-500 dark:text-slate-400">{demo.user}</span>
        </h1>
        <div className="mt-2 text-sm text-slate-500 dark:text-slate-400">
          Holdings, allocation, risk panels, and Aptivio readiness.
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="lg:col-span-2 space-y-4">
          <Card title="Balances">
            <div className="overflow-hidden rounded-xl border border-slate-200/70 dark:border-white/10">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 text-left text-xs text-slate-500 dark:bg-white/5 dark:text-slate-400">
                  <tr>
                    <th className="px-4 py-3">Asset</th>
                    <th className="px-4 py-3">Amount</th>
                    <th className="px-4 py-3">Value (USD)</th>
                    <th className="px-4 py-3">24h</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200/70 dark:divide-white/10">
                  {demo.balances.map((x) => (
                    <tr key={x.asset} className="text-slate-700 dark:text-slate-200">
                      <td className="px-4 py-3 font-medium">{x.asset}</td>
                      <td className="px-4 py-3">{x.amount}</td>
                      <td className="px-4 py-3">${x.value.toLocaleString()}</td>
                      <td className="px-4 py-3">
                        <span className="rounded-lg bg-emerald-500/10 px-2 py-1 text-xs text-emerald-600 dark:text-emerald-300">
                          {x.change24h}
                        </span>
                      </td>
                    </tr>
                  ))}
                  <tr className="bg-slate-50/60 text-slate-900 dark:bg-white/5 dark:text-white">
                    <td className="px-4 py-3 font-semibold" colSpan={2}>
                      Total
                    </td>
                    <td className="px-4 py-3 font-semibold">${total.toLocaleString()}</td>
                    <td className="px-4 py-3" />
                  </tr>
                </tbody>
              </table>
            </div>
          </Card>

          <Card title="Allocation (MVP)">
            <div className="space-y-3">
              {demo.balances.map((x) => {
                const pct = total ? Math.round((x.value / total) * 100) : 0;
                return (
                  <div key={x.asset}>
                    <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400">
                      <span>{x.asset}</span>
                      <span className="text-slate-700 dark:text-slate-200">{pct}%</span>
                    </div>
                    <div className="mt-2 h-2 w-full rounded-full bg-slate-200 dark:bg-white/10">
                      <div className="h-2 rounded-full bg-emerald-600" style={{ width: `${pct}%` }} />
                    </div>
                  </div>
                );
              })}
            </div>
          </Card>
        </div>

        <div className="space-y-4">
          <Card title="Aptivio Panel">
            <div className="text-sm text-slate-700 dark:text-slate-200">
              Score: <span className="font-semibold">{demo.aptivioScore}</span>
            </div>
            <div className="mt-1 text-xs text-slate-500 dark:text-slate-400">
              Status: <span className="font-medium">{demo.aptivioStatus}</span>
            </div>

            <div className="mt-4 rounded-xl bg-slate-50 px-3 py-3 text-xs text-slate-600 dark:bg-white/5 dark:text-slate-300">
              {demo.plan}
              <div className="mt-2 text-[11px] text-slate-500 dark:text-slate-400">
                Next: build a spending guardrail + debt-to-income target based on Nexus.
              </div>
            </div>

            <button className="mt-4 w-full rounded-xl bg-white px-4 py-2 text-sm text-slate-800 shadow-sm hover:bg-slate-50 dark:bg-white/5 dark:text-slate-200 dark:hover:bg-white/10">
              View Aptivio Nexus (demo)
            </button>
          </Card>

          <Card title="BNPL / Credit">
            <div className="text-sm text-slate-700 dark:text-slate-200">
              Exposure: <span className="font-semibold">${demo.bnpl.exposure.toLocaleString()}</span>
            </div>
            <div className="mt-1 text-xs text-slate-500 dark:text-slate-400">
              Next payment: ${demo.bnpl.nextPayment} • due in {demo.bnpl.dueInDays} days
            </div>

            <div className="mt-4 h-2 w-full rounded-full bg-slate-200 dark:bg-white/10">
              <div className="h-2 w-[32%] rounded-full bg-amber-500" />
            </div>

            <div className="mt-2 text-xs text-slate-500 dark:text-slate-400">
              Rule: block “silly” orders if they increase risk beyond policy.
            </div>
          </Card>

          <Card title="Quick Actions">
            <div className="grid gap-2">
              <button className="rounded-xl bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500">
                Deposit (demo)
              </button>
              <button className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm text-slate-800 hover:bg-slate-50 dark:border-white/10 dark:bg-white/5 dark:text-slate-200 dark:hover:bg-white/10">
                Withdraw (demo)
              </button>
              <button className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm text-slate-800 hover:bg-slate-50 dark:border-white/10 dark:bg-white/5 dark:text-slate-200 dark:hover:bg-white/10">
                Generate Statement (demo)
              </button>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
