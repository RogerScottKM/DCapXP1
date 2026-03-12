export default function AgentAdvisoryPage() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-slate-50 via-white to-indigo-50 dark:from-slate-950 dark:via-slate-950 dark:to-indigo-950/20">
      <div className="max-w-5xl mx-auto px-6 py-16 text-slate-900 dark:text-slate-100">
        <h1 className="text-4xl sm:text-5xl font-extrabold tracking-tight">
          Agent Advisory
        </h1>

        <p className="mt-6 text-lg text-slate-600 dark:text-slate-400 leading-relaxed">
          Hands-on help to design, test, and scale agent-native products.
          From architecture to compliance and prod reliability.
        </p>

        <section className="mt-10 grid gap-6 sm:grid-cols-3">
          <div className="rounded-2xl border border-slate-200 bg-white/80 p-6 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] backdrop-blur-md dark:border-slate-800/60 dark:bg-slate-950/40 dark:shadow-[0_0_0_1px_rgba(255,255,255,0.03)]">
            <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
              Architecture
            </h2>
            <p className="mt-2 text-slate-600 dark:text-slate-400">
              Protocol selection, trust layers, deterministic flows, LLM/agent orchestration.
            </p>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white/80 p-6 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] backdrop-blur-md dark:border-slate-800/60 dark:bg-slate-950/40 dark:shadow-[0_0_0_1px_rgba(255,255,255,0.03)]">
            <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
              Compliance
            </h2>
            <p className="mt-2 text-slate-600 dark:text-slate-400">
              ESG/fiduciary controls, auditability, policy-as-code.
            </p>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white/80 p-6 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] backdrop-blur-md dark:border-slate-800/60 dark:bg-slate-950/40 dark:shadow-[0_0_0_1px_rgba(255,255,255,0.03)]">
            <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
              Production
            </h2>
            <p className="mt-2 text-slate-600 dark:text-slate-400">
              SLAs, evals, load/chaos testing, incident playbooks.
            </p>
          </div>
        </section>
      </div>
    </main>
  );
}
