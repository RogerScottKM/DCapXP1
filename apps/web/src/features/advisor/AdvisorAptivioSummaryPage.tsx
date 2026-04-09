import React, { useEffect, useState } from "react";
import { useRouter } from "next/router";
import type { AdvisorAptivioSummaryResponse } from "@dcapx/contracts";
import { getAdvisorClientAptivioSummary } from "../../lib/api/advisor";
import PortalShell from "../ui/PortalShell";

function infoBox(kind: "error" | "info", message: string) {
  const classes =
    kind === "error"
      ? "border-rose-300 bg-rose-50 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200"
      : "border-cyan-300 bg-cyan-50 text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200";

  return (
    <div className={`rounded-2xl border px-4 py-3 text-sm ${classes}`}>
      {message}
    </div>
  );
}

function bandRow(label: string, value: string | number | null | undefined) {
  return (
    <div className="flex items-center justify-between gap-4 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 dark:border-slate-800 dark:bg-slate-950/60">
      <span className="text-sm text-slate-600 dark:text-slate-400">{label}</span>
      <span className="text-sm font-medium text-slate-900 dark:text-slate-100">
        {value ?? "—"}
      </span>
    </div>
  );
}

export default function AdvisorAptivioSummaryPage() {
  const router = useRouter();
  const clientId =
    typeof router.query.clientId === "string" ? router.query.clientId : "";

  const [data, setData] = useState<AdvisorAptivioSummaryResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!router.isReady || !clientId) return;

    let isMounted = true;

    async function load() {
      try {
        setIsLoading(true);
        setErrorMessage(null);

        const result = await getAdvisorClientAptivioSummary(clientId);
        if (isMounted) setData(result);
      } catch (error: any) {
        if (isMounted) {
          setErrorMessage(
            error?.error?.message ||
              error?.message ||
              "Failed to load advisor Aptivio summary."
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
  }, [router.isReady, clientId]);

  return (
    <PortalShell
      title="Advisor Aptivio Summary"
      description="Review the client’s consent-gated Aptivio summary, discussion flags, and adviser prompts."
    >
      <div className="grid gap-6">
        {isLoading ? (
          <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <p className="text-sm text-slate-600 dark:text-slate-400">
              Loading Aptivio summary...
            </p>
          </div>
        ) : null}

        {!isLoading && errorMessage ? infoBox("error", errorMessage) : null}

        {!isLoading && data ? (
          <>
            <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
              <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                <div>
                  <h2 className="text-xl font-semibold tracking-tight">
                    {data.clientDisplayName || "Client"}
                  </h2>
                  <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">
                    Adviser view of the latest consent-gated Aptivio profile summary.
                  </p>
                </div>

                <div className="rounded-full border border-slate-300 bg-slate-50 px-3 py-1 text-xs font-medium text-slate-700 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-200">
                  Consent: {data.consent.canViewSummary ? "Granted" : "Missing"}
                </div>
              </div>

              <div className="mt-6 rounded-2xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200">
                <span className="font-medium">{data.disclaimer.title}:</span>{" "}
                {data.disclaimer.body}
              </div>
            </section>

            {!data.consent.canViewSummary ? (
              infoBox("info", "This summary is unavailable because required client consent has not been recorded.")
            ) : null}

            {data.summary ? (
              <>
                <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
                  <h3 className="text-lg font-semibold tracking-tight">Top-Level Summary</h3>

                  <div className="mt-5 grid gap-3 md:grid-cols-2">
                    {bandRow("Assessment", `${data.summary.assessmentCode} v${data.summary.assessmentVersion}`)}
                    {bandRow("Assessed At", data.summary.assessedAtUtc)}
                    {bandRow("Overall Readiness Score", `${data.summary.scores.overallReadinessScore}/100`)}
                    {bandRow("Confidence", data.summary.confidenceLevel)}
                    {bandRow("Suitability", data.summary.suitability.status)}
                    {bandRow("Aptivio ID Status", data.summary.eligibility.aptivioIdStatus)}
                    {bandRow("Digital Twin Status", data.summary.eligibility.digitalTwinStatus)}
                    {bandRow("Risk Band", data.summary.bands.riskBand)}
                  </div>
                </section>

                <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
                  <h3 className="text-lg font-semibold tracking-tight">Profile Dimensions</h3>

                  <div className="mt-5 grid gap-3 md:grid-cols-2">
                    {bandRow("Loss Capacity", data.summary.bands.lossCapacityBand)}
                    {bandRow("Liquidity Need", data.summary.bands.liquidityNeedBand)}
                    {bandRow("Time Horizon", data.summary.bands.timeHorizonBand)}
                    {bandRow("Knowledge / Experience", data.summary.bands.knowledgeExperienceBand)}
                    {bandRow("Behavioural Stability", data.summary.bands.behaviouralStabilityBand)}
                  </div>
                </section>

                <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
                  <h3 className="text-lg font-semibold tracking-tight">Discussion Flags</h3>

                  {data.summary.flags.length === 0 ? (
                    <p className="mt-4 text-sm text-slate-600 dark:text-slate-400">
                      No discussion flags.
                    </p>
                  ) : (
                    <div className="mt-5 grid gap-4">
                      {data.summary.flags.map((flag) => (
                        <div
                          key={flag.code}
                          className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60"
                        >
                          <div className="flex items-center justify-between gap-4">
                            <div className="font-medium">{flag.title}</div>
                            <div className="rounded-full border border-slate-300 px-3 py-1 text-xs font-medium dark:border-slate-700">
                              {flag.severity}
                            </div>
                          </div>
                          <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">
                            {flag.description}
                          </p>
                        </div>
                      ))}
                    </div>
                  )}
                </section>

                <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
                  <h3 className="text-lg font-semibold tracking-tight">Adviser Prompts</h3>

                  {data.summary.prompts.length === 0 ? (
                    <p className="mt-4 text-sm text-slate-600 dark:text-slate-400">
                      No adviser prompts available.
                    </p>
                  ) : (
                    <div className="mt-5 grid gap-4">
                      {data.summary.prompts.map((prompt) => (
                        <div
                          key={prompt.code}
                          className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60"
                        >
                          <div className="font-medium">{prompt.label}</div>
                          <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">
                            {prompt.prompt}
                          </p>
                        </div>
                      ))}
                    </div>
                  )}
                </section>
              </>
            ) : null}
          </>
        ) : null}
      </div>
    </PortalShell>
  );
}

