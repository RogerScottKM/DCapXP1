#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p apps/web/pages
mkdir -p apps/web/src/features/auth
mkdir -p apps/web/src/features/onboarding
mkdir -p apps/web/src/lib/api

cat > apps/web/pages/register.tsx <<'EOF'
import RegisterPage from "../src/features/auth/RegisterPage";

export default RegisterPage;
EOF

cat > apps/web/src/lib/api/register.ts <<'EOF'
import { apiFetch } from "./client";

export interface RegisterClientRequest {
  email: string;
  username: string;
  firstName: string;
  lastName: string;
  phone: string;
  country: string;
}

export interface RegisterClientResponse {
  ok: true;
  user: {
    id: string;
    email: string;
    username: string;
  };
}

export function registerClient(body: RegisterClientRequest) {
  return apiFetch<RegisterClientResponse>("/api/auth/register", {
    method: "POST",
    body: JSON.stringify(body),
  });
}
EOF

cat > apps/web/src/lib/api/referrals.ts <<'EOF'
import { apiFetch } from "./client";

export const PENDING_REFERRAL_CODE_STORAGE_KEY = "dcapx_pending_referral_code";

export interface ReferralRewardBalanceDto {
  unitType: "POINTS" | "CASH" | "TOKEN" | "PROFIT_SHARE" | "STOCK_OPTION";
  balance: number;
  updatedAtUtc: string | null;
}

export interface ReferralAttributionDto {
  id: string;
  status: "PENDING" | "CONFIRMED" | "REJECTED" | "CANCELLED";
  applySource: "LOGIN" | "ONBOARDING" | "INVITATION" | "REGISTER" | "ADMIN" | "IMPORT" | null;
  referralCode: string;
  referrerUserId: string;
  attributedAtUtc: string;
  confirmedAtUtc: string | null;
  communityKey: string | null;
  regionKey: string | null;
}

export interface GetMyReferralStatusResponse {
  hasAttribution: boolean;
  canApplyReferralCode: boolean;
  lockedReason: string | null;
  referredByCodeInput: string | null;
  attribution: ReferralAttributionDto | null;
  rewards: {
    balances: ReferralRewardBalanceDto[];
    totals: {
      points: number;
      cash: number;
      token: number;
      profitShare: number;
      stockOption: number;
    };
  };
}

export interface ApplyReferralCodeRequest {
  code: string;
  applySource?: "LOGIN" | "ONBOARDING" | "INVITATION" | "REGISTER" | "ADMIN" | "IMPORT";
}

export interface ApplyReferralCodeResponse {
  ok: true;
  message: string;
  status: GetMyReferralStatusResponse;
}

export function applyReferralCode(body: ApplyReferralCodeRequest) {
  return apiFetch<ApplyReferralCodeResponse>("/api/referrals/apply", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function getMyReferralStatus() {
  return apiFetch<GetMyReferralStatusResponse>("/api/me/referral-status");
}
EOF

cat > apps/web/src/features/auth/RegisterPage.tsx <<'EOF'
import React, { useState } from "react";
import Link from "next/link";
import ThemeToggle from "../ui/ThemeToggle";
import { registerClient } from "../../lib/api/register";
import { requestPasswordReset } from "../../lib/api/auth";
import {
  PENDING_REFERRAL_CODE_STORAGE_KEY,
} from "../../lib/api/referrals";
import { friendlyPortalError } from "../../lib/api/friendlyError";

export default function RegisterPage() {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [devResetUrl, setDevResetUrl] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();

    const form = e.currentTarget;
    const formData = new FormData(form);

    const firstName = String(formData.get("firstName") || "").trim();
    const lastName = String(formData.get("lastName") || "").trim();
    const email = String(formData.get("email") || "").trim().toLowerCase();
    const phone = String(formData.get("phone") || "").trim();
    const username = String(formData.get("username") || "").trim();
    const country = String(formData.get("country") || "").trim().toUpperCase();
    const referralCode = String(formData.get("referralCode") || "").trim().toUpperCase();

    if (!firstName || !lastName || !email || !phone || !username || !country) {
      setErrorMessage("Please complete all required fields.");
      return;
    }

    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      setSuccessMessage(null);
      setDevResetUrl(null);

      await registerClient({
        firstName,
        lastName,
        email,
        phone,
        username,
        country,
      });

      if (referralCode) {
        localStorage.setItem(PENDING_REFERRAL_CODE_STORAGE_KEY, referralCode);
      } else {
        localStorage.removeItem(PENDING_REFERRAL_CODE_STORAGE_KEY);
      }

      const resetResult = await requestPasswordReset({ email });

      setSuccessMessage(
        "Account created successfully. Next, use the password setup link to secure your account."
      );

      if (resetResult.devResetUrl) {
        setDevResetUrl(resetResult.devResetUrl);
      }

      form.reset();
    } catch (error: any) {
      setErrorMessage(
        friendlyPortalError(error, "Failed to create account.")
      );
    } finally {
      setIsSubmitting(false);
    }
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
              Join the Agent-Native Economy
            </div>

            <h1 className="mt-6 text-4xl font-semibold leading-tight tracking-tight md:text-5xl">
              Create your DCapX account and start your onboarding journey.
            </h1>

            <p className="mt-5 max-w-xl text-base leading-7 text-slate-600 dark:text-slate-300">
              Set up your account details, optionally add a referral code, and we will
              send you a secure password setup link as the next step.
            </p>

            <div className="mt-8 grid gap-4 sm:grid-cols-3">
              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-900/70">
                <div className="text-sm font-medium">Growth-ready</div>
                <div className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                  Referral-aware onboarding from day one.
                </div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-900/70">
                <div className="text-sm font-medium">Compliance-first</div>
                <div className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                  Identity, KYC, and consent flow stay controlled.
                </div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-900/70">
                <div className="text-sm font-medium">Future-proof</div>
                <div className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                  Referral rewards can later expand into points, cash, or tokens.
                </div>
              </div>
            </div>
          </div>

          <div className="mx-auto w-full max-w-xl">
            <div className="rounded-3xl border border-slate-200 bg-white p-8 shadow-sm dark:border-slate-800 dark:bg-slate-900/85">
              <div className="mb-6">
                <h2 className="text-2xl font-semibold tracking-tight">Create account</h2>
                <p className="mt-2 text-sm text-slate-500 dark:text-slate-400">
                  New clients start here. We’ll send a password setup link after account creation.
                </p>
              </div>

              {errorMessage ? (
                <div className="mb-6 rounded-2xl border border-rose-300 bg-rose-50 px-4 py-3 text-sm text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200">
                  <span className="font-medium">Error:</span> {errorMessage}
                </div>
              ) : null}

              {successMessage ? (
                <div className="mb-6 rounded-2xl border border-emerald-300 bg-emerald-50 px-4 py-3 text-sm text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200">
                  <span className="font-medium">Success:</span> {successMessage}
                </div>
              ) : null}

              {devResetUrl ? (
                <div className="mb-6 rounded-2xl border border-cyan-300 bg-cyan-50 px-4 py-3 text-sm text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
                  <div className="font-medium">Development password setup link</div>
                  <a href={devResetUrl} className="mt-2 inline-block break-all underline">
                    {devResetUrl}
                  </a>
                </div>
              ) : null}

              <form onSubmit={handleSubmit} className="grid gap-5">
                <div className="grid gap-5 sm:grid-cols-2">
                  <div>
                    <label htmlFor="firstName" className="block text-sm font-medium text-slate-700 dark:text-slate-200">
                      First name
                    </label>
                    <input
                      id="firstName"
                      name="firstName"
                      type="text"
                      className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
                    />
                  </div>

                  <div>
                    <label htmlFor="lastName" className="block text-sm font-medium text-slate-700 dark:text-slate-200">
                      Last name
                    </label>
                    <input
                      id="lastName"
                      name="lastName"
                      type="text"
                      className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
                    />
                  </div>
                </div>

                <div className="grid gap-5 sm:grid-cols-2">
                  <div>
                    <label htmlFor="email" className="block text-sm font-medium text-slate-700 dark:text-slate-200">
                      Email
                    </label>
                    <input
                      id="email"
                      name="email"
                      type="email"
                      autoComplete="email"
                      className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
                    />
                  </div>

                  <div>
                    <label htmlFor="phone" className="block text-sm font-medium text-slate-700 dark:text-slate-200">
                      Phone
                    </label>
                    <input
                      id="phone"
                      name="phone"
                      type="text"
                      autoComplete="tel"
                      className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
                    />
                  </div>
                </div>

                <div className="grid gap-5 sm:grid-cols-2">
                  <div>
                    <label htmlFor="username" className="block text-sm font-medium text-slate-700 dark:text-slate-200">
                      Username
                    </label>
                    <input
                      id="username"
                      name="username"
                      type="text"
                      autoComplete="username"
                      className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
                    />
                  </div>

                  <div>
                    <label htmlFor="country" className="block text-sm font-medium text-slate-700 dark:text-slate-200">
                      Country
                    </label>
                    <input
                      id="country"
                      name="country"
                      type="text"
                      defaultValue="AU"
                      className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
                    />
                  </div>
                </div>

                <div>
                  <label htmlFor="referralCode" className="block text-sm font-medium text-slate-700 dark:text-slate-200">
                    Referral code <span className="text-slate-400">(optional)</span>
                  </label>
                  <input
                    id="referralCode"
                    name="referralCode"
                    type="text"
                    placeholder="TEAMSYDNEY01"
                    className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
                  />
                  <p className="mt-2 text-xs text-slate-500 dark:text-slate-400">
                    We’ll save this code and make it available during your first onboarding session.
                  </p>
                </div>

                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="w-full rounded-2xl border border-cyan-300 bg-cyan-50 px-4 py-3 font-medium text-cyan-800 transition hover:bg-cyan-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-cyan-400/40 dark:bg-cyan-400/10 dark:text-cyan-100 dark:hover:bg-cyan-400/20"
                >
                  {isSubmitting ? "Creating account..." : "Create Account"}
                </button>
              </form>

              <div className="mt-6 text-sm text-slate-500 dark:text-slate-400">
                Already have an account?{" "}
                <Link href="/login" className="font-medium text-cyan-700 underline dark:text-cyan-300">
                  Log in
                </Link>
              </div>
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
EOF

cat > apps/web/src/features/onboarding/ReferralCard.tsx <<'EOF'
import React, { useEffect, useState } from "react";
import { useRouter } from "next/router";
import type { OnboardingStatusResponse } from "@dcapx/contracts";
import {
  applyReferralCode,
  PENDING_REFERRAL_CODE_STORAGE_KEY,
} from "../../lib/api/referrals";
import { friendlyPortalError } from "../../lib/api/friendlyError";

type Props = {
  referral: OnboardingStatusResponse["entities"]["referral"];
};

export default function ReferralCard({ referral }: Props) {
  const router = useRouter();

  const [code, setCode] = useState("");
  const [isApplying, setIsApplying] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!referral.canApplyReferralCode) return;
    const stored = localStorage.getItem(PENDING_REFERRAL_CODE_STORAGE_KEY);
    if (stored && !code) {
      setCode(stored);
    }
  }, [referral.canApplyReferralCode, code]);

  async function handleApply(e: React.FormEvent) {
    e.preventDefault();

    const normalized = code.trim().toUpperCase();
    if (!normalized) {
      setErrorMessage("Please enter a referral code.");
      return;
    }

    try {
      setIsApplying(true);
      setErrorMessage(null);
      setSuccessMessage(null);

      await applyReferralCode({
        code: normalized,
        applySource: "ONBOARDING",
      });

      localStorage.removeItem(PENDING_REFERRAL_CODE_STORAGE_KEY);
      setSuccessMessage("Referral code applied successfully.");

      setTimeout(() => {
        router.replace(router.asPath);
      }, 500);
    } catch (error: any) {
      setErrorMessage(
        friendlyPortalError(error, "Failed to apply referral code.")
      );
    } finally {
      setIsApplying(false);
    }
  }

  function handleClearPending() {
    localStorage.removeItem(PENDING_REFERRAL_CODE_STORAGE_KEY);
    setCode("");
    setSuccessMessage(null);
    setErrorMessage(null);
  }

  if (!referral.canApplyReferralCode) {
    return (
      <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <h2 className="text-xl font-semibold tracking-tight">Referral</h2>
            <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">
              Your referral attribution is already recorded.
            </p>
          </div>

          <span className="rounded-full border border-cyan-300 bg-cyan-50 px-3 py-1 text-xs font-medium text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
            {referral.attributionStatus ?? "RECORDED"}
          </span>
        </div>

        <div className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
            <div className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Applied Code
            </div>
            <div className="mt-2 text-sm font-semibold">
              {referral.appliedCode ?? "—"}
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
            <div className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Referrer User
            </div>
            <div className="mt-2 text-sm font-semibold break-all">
              {referral.referrerUserId ?? "—"}
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
            <div className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Status
            </div>
            <div className="mt-2 text-sm font-semibold">
              {referral.attributionStatus ?? "—"}
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
            <div className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Points Balance
            </div>
            <div className="mt-2 text-sm font-semibold">
              {referral.pointsBalance ?? 0}
            </div>
          </div>
        </div>
      </section>
    );
  }

  return (
    <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h2 className="text-xl font-semibold tracking-tight">Have a referral code?</h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">
            Apply it once to lock in your referral attribution and future rewards pathway.
          </p>
        </div>

        <span className="rounded-full border border-slate-300 bg-slate-100 px-3 py-1 text-xs font-medium text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300">
          Optional
        </span>
      </div>

      {errorMessage ? (
        <div className="mt-5 rounded-2xl border border-rose-300 bg-rose-50 px-4 py-3 text-sm text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200">
          <strong>Error:</strong> {errorMessage}
        </div>
      ) : null}

      {successMessage ? (
        <div className="mt-5 rounded-2xl border border-emerald-300 bg-emerald-50 px-4 py-3 text-sm text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200">
          <strong>Success:</strong> {successMessage}
        </div>
      ) : null}

      <form onSubmit={handleApply} className="mt-5 flex flex-col gap-4 md:flex-row md:items-end">
        <div className="w-full md:max-w-sm">
          <label
            htmlFor="referralCode"
            className="block text-sm font-medium text-slate-700 dark:text-slate-200"
          >
            Referral code
          </label>
          <input
            id="referralCode"
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            placeholder="TEAMSYDNEY01"
            className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none placeholder:text-slate-400 focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
          />
        </div>

        <div className="flex flex-wrap gap-3">
          <button
            type="submit"
            disabled={isApplying}
            className="rounded-2xl border border-cyan-300 bg-cyan-50 px-5 py-3 text-sm font-medium text-cyan-800 transition hover:bg-cyan-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-cyan-400/40 dark:bg-cyan-400/10 dark:text-cyan-100 dark:hover:bg-cyan-400/20"
          >
            {isApplying ? "Applying..." : "Apply referral code"}
          </button>

          <button
            type="button"
            onClick={handleClearPending}
            className="rounded-2xl border border-slate-300 bg-white px-5 py-3 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            Clear
          </button>
        </div>
      </form>
    </section>
  );
}
EOF

cat > apps/web/src/features/onboarding/OnboardingPage.tsx <<'EOF'
import React, { useEffect, useState } from "react";
import Link from "next/link";
import type { OnboardingStatusResponse } from "@dcapx/contracts";
import { getMyOnboardingStatus } from "../../lib/api/onboarding";
import { friendlyPortalError } from "../../lib/api/friendlyError";
import OnboardingProgress from "./OnboardingProgress";
import ReferralCard from "./ReferralCard";
import PortalShell from "../ui/PortalShell";

export default function OnboardingPage() {
  const [data, setData] = useState<OnboardingStatusResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;

    async function load() {
      try {
        setIsLoading(true);
        setErrorMessage(null);

        const result = await getMyOnboardingStatus();
        if (isMounted) setData(result);
      } catch (error: any) {
        if (isMounted) {
          setErrorMessage(
            friendlyPortalError(error, "Failed to load onboarding status.")
          );
        }
      } finally {
        if (isMounted) setIsLoading(false);
      }
    }

    load();

    return () => {
      isMounted = false;
    };
  }, []);

  const isAuthError = errorMessage === "Please sign in to continue.";

  return (
    <PortalShell
      title="Client Onboarding"
      description="Track your onboarding progress, complete the next required action, and move through identity, consent, and Aptivio readiness workflow steps."
    >
      <div className="grid gap-6">
        {isLoading ? (
          <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <p className="text-sm text-slate-600 dark:text-slate-400">
              Loading onboarding status...
            </p>
          </div>
        ) : null}

        {!isLoading && errorMessage ? (
          <div className="rounded-3xl border border-rose-300 bg-rose-50 p-6 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200">
            <strong>Error:</strong> {errorMessage}
          </div>
        ) : null}

        {!isLoading && isAuthError ? (
          <div className="rounded-3xl border border-cyan-300 bg-cyan-50 p-6 text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
            Please sign in first to view your onboarding progress.{" "}
            <Link href="/login" className="font-medium underline">
              Go to login
            </Link>
          </div>
        ) : null}

        {!isLoading && !isAuthError && !errorMessage && data ? (
          <>
            <ReferralCard referral={data.entities.referral} />
            <OnboardingProgress data={data} />
          </>
        ) : null}
      </div>
    </PortalShell>
  );
}
EOF

cat > apps/web/src/features/auth/LoginPage.tsx <<'EOF'
import React, { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/router";
import { getSession, login } from "../../lib/api/auth";
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
EOF

echo
echo "✅ Register + referral UI pack written."
echo "Next:"
echo "  pnpm --filter web build"
echo "or"
echo "  pnpm --filter web exec next dev -H 0.0.0.0 -p 3002"
