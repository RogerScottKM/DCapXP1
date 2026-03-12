export default function FoundationPage() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-white via-slate-50 to-indigo-50 text-slate-900 dark:from-slate-950 dark:via-slate-950 dark:to-indigo-950/20 dark:text-slate-100">
      <div className="mx-auto max-w-5xl px-6 py-12">
        <div className="inline-flex items-center rounded-full border border-slate-200 bg-white px-3 py-1 text-xs text-slate-700 dark:border-slate-800/60 dark:bg-slate-950/30 dark:text-slate-300">
          About Us
        </div>

        <h1 className="mt-6 text-4xl font-semibold tracking-tight md:text-6xl">
          From Tokenization to Autonomy: Our Mission
        </h1>

        <p className="mt-6 text-lg text-slate-700 dark:text-slate-300">
          DCapX was built on the belief that tokenization will define the next era of finance — and that autonomous AI
          agents will become primary economic actors. Our mission is to build secure, scalable, and ethically governed
          exchange infrastructure that bridges human wealth with the agent economy.
        </p>

        <div className="mt-10 space-y-6">
          <section className="rounded-2xl border border-slate-200/70 bg-white/70 p-8 shadow-sm backdrop-blur-md dark:border-slate-800/60 dark:bg-slate-950/40">
            <h2 className="text-2xl font-semibold">Principles</h2>

            <ul className="mt-4 list-disc space-y-2 pl-6 text-slate-700 dark:text-slate-300">
              <li>
                <b>Foresight & Innovation:</b> infrastructure-first, tokenized ownership.
              </li>
              <li>
                <b>Fiduciary & Ethics:</b> banking-grade discipline embedded into systems and controls.
              </li>
              <li>
                <b>Scalability & Trust:</b> architecture beyond L1/L2 limits — auditable settlement and clear governance.
              </li>
            </ul>
          </section>

          <section className="rounded-2xl border border-slate-200/70 bg-white/70 p-8 shadow-sm backdrop-blur-md dark:border-slate-800/60 dark:bg-slate-950/40">
            <h2 className="text-2xl font-semibold">Contact</h2>
            <p className="mt-3 text-slate-700 dark:text-slate-300">
              Advisory, partnerships, or media:{" "}
              <a className="underline underline-offset-4" href="mailto:hello@dcapital.global">
                hello@dcapital.global
              </a>
            </p>
          </section>
        </div>
      </div>
    </main>
  );
}
