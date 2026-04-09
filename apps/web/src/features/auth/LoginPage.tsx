import React, { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/router";
import { getSession, login } from "../../lib/api/auth";
import {
  applyReferralCode,
  getMyReferralStatus,
  PENDING_REFERRAL_CODE_STORAGE_KEY,
  setReferralApplyFeedback,
} from "../../lib/api/referrals";
import ThemeToggle from "../ui/ThemeToggle";
import { friendlyPortalError } from "../../lib/api/friendlyError";

export default function LoginPage() {
  const router = useRouter();

  const [isCheckingSession, setIsCheckingSession] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
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

  async function tryAutoApplyPendingReferral() {
    if (typeof window === "undefined") return;

    const pending = localStorage.getItem(PENDING_REFERRAL_CODE_STORAGE_KEY)?.trim().toUpperCase();
    if (!pending) return;

    try {
      const status = await getMyReferralStatus();

      if (!status.canApplyReferralCode) {
        localStorage.removeItem(PENDING_REFERRAL_CODE_STORAGE_KEY);
        return;
      }

      await applyReferralCode({
        code: pending,
        applySource: "LOGIN",
      });

      localStorage.removeItem(PENDING_REFERRAL_CODE_STORAGE_KEY);
      setReferralApplyFeedback({
        kind: "success",
        message: `Referral code ${pending} was automatically applied after sign-in.`,
      });
    } catch {
      setReferralApplyFeedback({
        kind: "error",
        message:
          "We could not auto-apply your saved referral code. You can still apply it manually from onboarding.",
      });
    }
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();

    const form = e.currentTarget;
    const formData = new FormData(form);

    const identifier = String(formData.get("identifier") || "").trim();
    const password = String(formData.get("password") || "");

    if (!identifier || !password) {
      setErrorMessage("Please enter your email/username and password.");
      return;
    }

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await login({ identifier, password });
      await tryAutoApplyPendingReferral();

      router.push("/app/onboarding");
    } catch (error: any) {
      setErrorMessage(friendlyPortalError(error, "Login failed."));
    } finally {
      setIsSubmitting(false);
    }
  }

  if (isCheckingSession) {
    return (
      <main className="min-h-screen bg-white text-slate-900 dark:bg-slate-950 dark:text-slate-100">
        <div className="mx-auto flex min-h-screen max-w-7xl items-center justify-center px-6 py-8">
          <div className="w-full max-w-md rounded-3xl border border-slate-200 bg-white p-8 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <div className="text-2xl font-semibold tracking-tight">DCapX</div>
            <p className="mt-3 text-sm text-slate-500 dark:text-slate-400">
              Checking session...
            </p>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-white text-slate-900 dark:bg-slate-950 dark:text-slate-100">
      <div className="mx-auto flex min-h-screen max-w-7xl flex-col px-6 py-8">
        <header className="flex items-center justify-between border-b border-slate-200 pb-5 dark:border-slate-800">
          <Link href="/" className="text-xl font-semibold tracking-tight">
            DCapX
          </Link>

          <div className="flex items-center gap-4">
            <nav className="hidden gap-6 text-sm text-slate-600 dark:text-slate-300 md:flex">
              <Link href="/foundation" className="transition hover:text-slate-900 dark:hover:text-white">
                Foundation
              </Link>
              <Link href="/agent-advisory" className="transition hover:text-slate-900 dark:hover:text-white">
                Agent Advisory
              </Link>
              <Link href="/dashboard" className="transition hover:text-slate-900 dark:hover:text-white">
                Dashboard
              </Link>
              <Link href="/exchange" className="transition hover:text-slate-900 dark:hover:text-white">
                Exchange
              </Link>
              <Link href="/portfolio" className="transition hover:text-slate-900 dark:hover:text-white">
                Portfolio
              </Link>
              <Link href="/account" className="transition hover:text-slate-900 dark:hover:text-white">
                Account
              </Link>
            </nav>

            <ThemeToggle />
          </div>
        </header>

        <section className="grid flex-1 items-center gap-12 py-12 md:grid-cols-2">
          <div className="max-w-2xl">
            <div className="inline-flex rounded-full border border-cyan-300 bg-cyan-50 px-3 py-1 text-xs font-semibold tracking-wide text-cyan-800 dark:border-cyan-400/25 dark:bg-cyan-400/10 dark:text-cyan-200">
              Agent-Native Exchange Access
            </div>

            <h1 className="mt-6 text-4xl font-semibold leading-tight tracking-tight md:text-5xl">
              Secure access to the DCapX onboarding and account portal.
            </h1>

            <p className="mt-5 max-w-xl text-base leading-7 text-slate-600 dark:text-slate-300">
              Continue your client onboarding, KYC submission, consent workflow,
              and Aptivio-led readiness journey through a controlled,
              compliance-aware access point.
            </p>

            <div className="mt-8 grid gap-4 sm:grid-cols-3">
              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-900/70">
                <div className="text-sm font-medium">Deterministic</div>
                <div className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                  Controlled workflow and next-step guidance.
                </div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-900/70">
                <div className="text-sm font-medium">Guardrailed</div>
                <div className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                  Consent-aware and policy-aware onboarding.
                </div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-900/70">
                <div className="text-sm font-medium">Auditable</div>
                <div className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                  KYC, identity, and advisory workflow traceability.
                </div>
              </div>
            </div>
          </div>

          <div className="mx-auto w-full max-w-md">
            <div className="rounded-3xl border border-slate-200 bg-white p-8 shadow-sm dark:border-slate-800 dark:bg-slate-900/85">
              <div className="mb-6">
                <h2 className="text-2xl font-semibold tracking-tight">Log in</h2>
                <p className="mt-2 text-sm text-slate-500 dark:text-slate-400">
                  Existing clients sign in here.
                </p>
              </div>

              {errorMessage ? (
                <div className="mb-6 rounded-2xl border border-rose-300 bg-rose-50 px-4 py-3 text-sm text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200">
                  <span className="font-medium">Error:</span> {errorMessage}
                </div>
              ) : null}

              <form onSubmit={handleSubmit} className="space-y-5">
                <div>
                  <label
                    htmlFor="identifier"
                    className="block text-sm font-medium text-slate-700 dark:text-slate-200"
                  >
                    Email or Username
                  </label>
                  <input
                    id="identifier"
                    name="identifier"
                    type="text"
                    placeholder="pedro.vx.km@gmail.com"
                    autoComplete="username"
                    className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white dark:placeholder:text-slate-500"
                  />
                </div>

                <div>
                  <div className="flex items-center justify-between gap-3">
                    <label
                      htmlFor="password"
                      className="block text-sm font-medium text-slate-700 dark:text-slate-200"
                    >
                      Password
                    </label>

                    <div className="flex items-center gap-3">
                      <Link
                        href="/forgot-password"
                        className="text-xs font-semibold text-cyan-700 transition hover:text-cyan-800 dark:text-cyan-300 dark:hover:text-cyan-200"
                      >
                        Forgot password?
                      </Link>

                      <button
                        type="button"
                        onClick={() => setShowPassword((v) => !v)}
                        className="text-xs font-semibold text-cyan-700 transition hover:text-cyan-800 dark:text-cyan-300 dark:hover:text-cyan-200"
                      >
                        {showPassword ? "Hide" : "Show"} password
                      </button>
                    </div>
                  </div>

                  <input
                    id="password"
                    name="password"
                    type={showPassword ? "text" : "password"}
                    placeholder="Enter your password"
                    autoComplete="current-password"
                    className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white dark:placeholder:text-slate-500"
                  />
                </div>

                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="w-full rounded-2xl border border-cyan-300 bg-cyan-50 px-4 py-3 font-medium text-cyan-800 transition hover:bg-cyan-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-cyan-400/40 dark:bg-cyan-400/10 dark:text-cyan-100 dark:hover:bg-cyan-400/20"
                >
                  {isSubmitting ? "Signing in..." : "Sign In"}
                </button>
              </form>

              <div className="mt-6 rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
                <div className="text-sm font-medium text-slate-900 dark:text-slate-100">
                  New here?
                </div>
                <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                  Create your account first. You can add a referral code during account creation.
                </p>
                <Link
                  href="/register"
                  className="mt-3 inline-flex rounded-2xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
                >
                  Create account
                </Link>
              </div>

              <div className="mt-6 text-xs text-slate-500 dark:text-slate-500">
                Protected access for DCapX onboarding, KYC, and advisory workflows.
              </div>
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
