import React, { useEffect, useState } from "react";
import { useRouter } from "next/router";
import type { OnboardingStatusResponse } from "@dcapx/contracts";
import {
  applyReferralCode,
  popReferralApplyFeedback,
  PENDING_REFERRAL_CODE_STORAGE_KEY,
} from "../../lib/api/referrals";
import { friendlyPortalError } from "../../lib/api/friendlyError";

type Props = {
  referral: OnboardingStatusResponse["entities"]["referral"];
};

function MetricCard({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
      <div className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">
        {label}
      </div>
      <div className="mt-2 text-sm font-semibold break-all">{value}</div>
    </div>
  );
}

export default function ReferralCard({ referral }: Props) {
  const router = useRouter();

  const [code, setCode] = useState("");
  const [isApplying, setIsApplying] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  useEffect(() => {
    const feedback = popReferralApplyFeedback();
    if (feedback) {
      if (feedback.kind === "success") {
        setSuccessMessage(feedback.message);
      } else {
        setErrorMessage(feedback.message);
      }
    }
  }, []);

  useEffect(() => {
    if (!referral.canApplyReferralCode) return;

    const stored =
      typeof window !== "undefined"
        ? localStorage.getItem(PENDING_REFERRAL_CODE_STORAGE_KEY)
        : null;

    if (stored && !code) {
      setCode(stored.toUpperCase());
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

      if (typeof window !== "undefined") {
        localStorage.removeItem(PENDING_REFERRAL_CODE_STORAGE_KEY);
      }

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
    if (typeof window !== "undefined") {
      localStorage.removeItem(PENDING_REFERRAL_CODE_STORAGE_KEY);
    }
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
              Your referral attribution is already recorded and attached to this account.
            </p>
          </div>

          <span className="rounded-full border border-cyan-300 bg-cyan-50 px-3 py-1 text-xs font-medium text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
            {referral.attributionStatus ?? "RECORDED"}
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

        <div className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard label="Applied Code" value={referral.appliedCode ?? "—"} />
          <MetricCard label="Referrer User" value={referral.referrerUserId ?? "—"} />
          <MetricCard label="Status" value={referral.attributionStatus ?? "—"} />
          <MetricCard label="Points Balance" value={referral.pointsBalance ?? 0} />
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
