// apps/web/app/page.tsx
import Link from "next/link";

export default function Home() {
  return (
    <section className="min-h-[70vh] bg-gradient-to-br from-slate-50 via-white to-indigo-50 dark:from-[#0b1020] dark:via-slate-950 dark:to-indigo-950/30">
      <div className="mx-auto max-w-6xl px-6 py-16">
        <span className="inline-block rounded-full border border-slate-200 bg-white/70 px-3 py-1 text-sm text-slate-700 backdrop-blur dark:border-white/10 dark:bg-white/10 dark:text-slate-200">
          DCapX
        </span>

        <h1 className="mt-6 text-5xl font-extrabold leading-tight tracking-tight text-slate-900 dark:text-white">
          Agent-Native Exchange for Autonomous Finance
        </h1>

        <p className="mt-6 max-w-3xl text-lg text-slate-600 dark:text-white/80">
          The first agent-native digital exchange, built to power the trillion-dollar swarm of autonomous AI agents.
          We are the foundational layers of finance—designed for machine-to-machine trust, efficiency, and
          hyper-parallel settlement. Health endpoint:{" "}
          <code className="mx-1 rounded bg-slate-900/5 px-1 text-slate-800 dark:bg-white/10 dark:text-white">
            /api/health
          </code>
          .
        </p>

        <div className="mt-8 flex flex-wrap gap-3">
          <Link
            href="/markets/BTC-USD"
            className="rounded-xl bg-indigo-600 px-5 py-3 font-medium text-white hover:bg-indigo-500"
          >
            Launch Exchange
          </Link>

          <Link
            href="/dashboard"
            className="rounded-xl border border-slate-200 bg-white/70 px-5 py-3 font-medium text-slate-800 hover:bg-white dark:border-white/15 dark:bg-white/5 dark:text-white dark:hover:bg-white/10"
          >
            View Dashboard
          </Link>

          <a
            href="/api/health"
            className="rounded-xl border border-emerald-500/40 bg-emerald-500/5 px-5 py-3 font-medium text-emerald-700 hover:bg-emerald-500/10 dark:border-emerald-500/30 dark:bg-transparent dark:text-emerald-300 dark:hover:bg-emerald-500/10"
          >
            API Health
          </a>
        </div>

        {/* Product cards */}
        <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div className="rounded-2xl border border-slate-200 bg-white/70 p-5 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] backdrop-blur dark:border-white/10 dark:bg-white/5 dark:shadow-none">
            <h3 className="text-lg font-semibold text-slate-900 dark:text-white">Deterministic Settlement</h3>
            <p className="mt-2 text-sm text-slate-600 dark:text-white/70">
              Price-time priority order book with tamper-evident logs and monthly proof bundles.
            </p>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white/70 p-5 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] backdrop-blur dark:border-white/10 dark:bg-white/5 dark:shadow-none">
            <h3 className="text-lg font-semibold text-slate-900 dark:text-white">Guardrailed Agents</h3>
            <p className="mt-2 text-sm text-slate-600 dark:text-white/70">
              Constraint-programmed policy envelopes, human-in-the-loop overrides, and kill-switch drills.
            </p>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white/70 p-5 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] backdrop-blur dark:border-white/10 dark:bg-white/5 dark:shadow-none">
            <h3 className="text-lg font-semibold text-slate-900 dark:text-white">Treasury & RVXG (Gold)</h3>
            <p className="mt-2 text-sm text-slate-600 dark:text-white/70">
              Programmable treasuries with tokenized gold sleeves and independent custody attestations.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
