import React from "react";
import Link from "next/link";
import type { OnboardingStatusResponse, OnboardingStepDto } from "@dcapx/contracts";

type Props = {
  data: OnboardingStatusResponse;
};

function formatUtc(utc: string | null | undefined) {
  if (!utc) return "—";

  const date = new Date(utc);
  if (Number.isNaN(date.getTime())) return utc;

  return new Intl.DateTimeFormat("en-AU", {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(date);
}

function statusClasses(status: string) {
  switch (status) {
    case "COMPLETED":
      return "border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200";
    case "IN_PROGRESS":
      return "border-cyan-300 bg-cyan-50 text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200";
    case "LOCKED":
      return "border-slate-300 bg-slate-100 text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300";
    case "FAILED":
    case "BLOCKED":
      return "border-rose-300 bg-rose-50 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200";
    default:
      return "border-amber-300 bg-amber-50 text-amber-700 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200";
  }
}

function nextStepHref(stepCode: string | null) {
  switch (stepCode) {
    case "CONTACT_VERIFIED":
      return "/app/verify-contact";
    case "CONSENTS_ACCEPTED":
      return "/app/consents";
    case "KYC_SUBMITTED":
    case "KYC_APPROVED":
      return "/app/kyc";
    default:
      return null;
  }
}
function StepCard({ step }: { step: OnboardingStepDto }) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900/70">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h3 className="text-base font-semibold">{step.label}</h3>
          <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">
            Required: {step.required ? "Yes" : "No"}
          </p>
        </div>

        <span
          className={`rounded-full border px-3 py-1 text-xs font-medium ${statusClasses(step.status)}`}
        >
          {step.status}
        </span>
      </div>

      {step.completedAtUtc ? (
        <p className="mt-4 text-sm text-slate-600 dark:text-slate-400">
          Completed: {formatUtc(step.completedAtUtc)}
        </p>
      ) : null}
    </div>
  );
}

export default function OnboardingProgress({ data }: Props) {
  const nextHref = nextStepHref(data.currentStep);

  return (
    <section className="grid gap-6">
      <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
        <div className="grid gap-5 md:grid-cols-3">
          <div>
            <div className="text-sm text-slate-500 dark:text-slate-400">Overall Status</div>
            <div className="mt-2 text-2xl font-semibold">{data.overallStatus}</div>
          </div>

          <div>
            <div className="text-sm text-slate-500 dark:text-slate-400">Completion</div>
            <div className="mt-2 text-2xl font-semibold">{data.completionPercent}%</div>
          </div>

          <div>
            <div className="text-sm text-slate-500 dark:text-slate-400">Next Step</div>
            <div className="mt-2 text-base font-medium">
              {data.nextRecommendedAction?.label || "Continue onboarding"}
            </div>
          </div>
        </div>

        <div className="mt-6 h-3 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800">
          <div
            className="h-full rounded-full bg-cyan-500 transition-all"
            style={{ width: `${data.completionPercent}%` }}
          />
        </div>

        <div className="mt-6 flex flex-wrap gap-3">
          {nextHref ? (
            <Link
              href={nextHref}
              className="rounded-2xl border border-cyan-400/40 bg-cyan-400/10 px-4 py-2 text-sm font-medium text-cyan-700 transition hover:bg-cyan-400/20 dark:text-cyan-200"
            >
              Continue Next Step
            </Link>
          ) : null}

          <Link
            href="/app/consents"
            className="rounded-2xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            View Consents
          </Link>

          <Link
            href="/app/kyc"
            className="rounded-2xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            View KYC
          </Link>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {data.steps.map((step) => (
          <StepCard key={step.code} step={step} />
        ))}
      </div>
    </section>
  );
}
