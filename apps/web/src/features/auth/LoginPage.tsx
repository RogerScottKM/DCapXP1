import React, { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/router";
import { getSession, login } from "../../lib/api/auth";

export default function LoginPage() {
  const router = useRouter();

  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [isCheckingSession, setIsCheckingSession] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;

    async function checkSession() {
      try {
        await getSession();
        if (isMounted) router.replace("/app/onboarding");
      } catch {
        // Not signed in yet.
      } finally {
        if (isMounted) setIsCheckingSession(false);
      }
    }

    checkSession();

    return () => {
      isMounted = false;
    };
  }, [router]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await login({ identifier, password });

      router.push("/app/onboarding");
    } catch (error: any) {
      setErrorMessage(
        error?.error?.message ||
          error?.message ||
          "Login failed."
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  if (isCheckingSession) {
    return (
      <main className="min-h-screen bg-slate-950 text-white">
        <div className="mx-auto flex min-h-screen max-w-7xl items-center justify-center px-6 py-8">
          <div className="w-full max-w-md rounded-3xl border border-slate-800 bg-slate-900/80 p-8 shadow-2xl backdrop-blur">
            <div className="text-2xl font-semibold tracking-tight">DCapX</div>
            <p className="mt-3 text-sm text-slate-400">Checking session...</p>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-slate-950 text-white">
      <div className="mx-auto flex min-h-screen max-w-7xl flex-col px-6 py-8">
        <header className="flex items-center justify-between border-b border-slate-800 pb-5">
          <Link href="/" className="text-xl font-semibold tracking-tight">
            DCapX
          </Link>

          <nav className="hidden gap-6 text-sm text-slate-300 md:flex">
            <Link href="/foundation" className="transition hover:text-white">
              Foundation
            </Link>
            <Link href="/agent-advisory" className="transition hover:text-white">
              Agent Advisory
            </Link>
            <Link href="/dashboard" className="transition hover:text-white">
              Dashboard
            </Link>
            <Link href="/exchange" className="transition hover:text-white">
              Exchange
            </Link>
            <Link href="/portfolio" className="transition hover:text-white">
              Portfolio
            </Link>
            <Link href="/account" className="transition hover:text-white">
              Account
            </Link>
          </nav>
        </header>

        <section className="grid flex-1 items-center gap-12 py-12 md:grid-cols-2">
          <div className="max-w-2xl">
            <div className="inline-flex rounded-full border border-cyan-400/25 bg-cyan-400/10 px-3 py-1 text-xs font-medium tracking-wide text-cyan-200">
              Agent-Native Exchange Access
            </div>

            <h1 className="mt-6 text-4xl font-semibold leading-tight tracking-tight md:text-5xl">
              Secure access to the DCapX onboarding and account portal.
            </h1>

            <p className="mt-5 max-w-xl text-base leading-7 text-slate-300">
              Continue your client onboarding, KYC submission, consent workflow,
              and Aptivio-led readiness journey through a controlled,
              compliance-aware access point.
            </p>

            <div className="mt-8 grid gap-4 sm:grid-cols-3">
              <div className="rounded-2xl border border-slate-800 bg-slate-900/70 p-4">
                <div className="text-sm font-medium text-white">Deterministic</div>
                <div className="mt-1 text-sm text-slate-400">
                  Controlled workflow and next-step guidance.
                </div>
              </div>

              <div className="rounded-2xl border border-slate-800 bg-slate-900/70 p-4">
                <div className="text-sm font-medium text-white">Guardrailed</div>
                <div className="mt-1 text-sm text-slate-400">
                  Consent-aware and policy-aware onboarding.
                </div>
              </div>

              <div className="rounded-2xl border border-slate-800 bg-slate-900/70 p-4">
                <div className="text-sm font-medium text-white">Auditable</div>
                <div className="mt-1 text-sm text-slate-400">
                  KYC, identity, and advisory workflow traceability.
                </div>
              </div>
            </div>
          </div>

          <div className="mx-auto w-full max-w-md">
            <div className="rounded-3xl border border-slate-800 bg-slate-900/85 p-8 shadow-2xl backdrop-blur">
              <div className="mb-6">
                <h2 className="text-2xl font-semibold tracking-tight">Sign in</h2>
                <p className="mt-2 text-sm text-slate-400">
                  Access your DCapX client workspace.
                </p>
              </div>

              {errorMessage ? (
                <div className="mb-6 rounded-2xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
                  <span className="font-medium">Error:</span> {errorMessage}
                </div>
              ) : null}

              <form onSubmit={handleSubmit} className="space-y-5">
                <div>
                  <label
                    htmlFor="identifier"
                    className="block text-sm font-medium text-slate-200"
                  >
                    Email or Username
                  </label>
                  <input
                    id="identifier"
                    type="text"
                    value={identifier}
                    onChange={(e) => setIdentifier(e.target.value)}
                    placeholder="pedro.vx.km@gmail.com"
                    autoComplete="username"
                    className="mt-2 w-full rounded-2xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none placeholder:text-slate-500 focus:border-cyan-400"
                  />
                </div>

                <div>
                  <label
                    htmlFor="password"
                    className="block text-sm font-medium text-slate-200"
                  >
                    Password
                  </label>
                  <input
                    id="password"
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Enter your password"
                    autoComplete="current-password"
                    className="mt-2 w-full rounded-2xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none placeholder:text-slate-500 focus:border-cyan-400"
                  />
                </div>

                <button
                  type="submit"
                  disabled={isSubmitting || !identifier || !password}
                  className="w-full rounded-2xl border border-cyan-400/40 bg-cyan-400/10 px-4 py-3 font-medium text-cyan-100 transition hover:bg-cyan-400/20 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {isSubmitting ? "Signing in..." : "Sign In"}
                </button>
              </form>

              <div className="mt-6 text-xs text-slate-500">
                Protected access for DCapX onboarding, KYC, and advisory workflows.
              </div>
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
