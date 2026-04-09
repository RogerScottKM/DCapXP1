import type { ReactNode } from "react";
import { useEffect, useState } from "react";
import { fetchPortalSummary, type PortalSummary } from "../../lib/api/portalSummary";

function badgeClasses(kind: "emerald" | "amber" | "slate" | "cyan") {
  switch (kind) {
    case "emerald":
      return "border-emerald-500/40 bg-emerald-500/10 text-emerald-200";
    case "amber":
      return "border-amber-500/40 bg-amber-500/10 text-amber-200";
    case "cyan":
      return "border-cyan-500/40 bg-cyan-500/10 text-cyan-200";
    default:
      return "border-white/10 bg-white/[0.03] text-slate-200";
  }
}

function inferKycKind(status: string | null): "emerald" | "amber" | "slate" {
  const value = String(status ?? "").toUpperCase();
  if (["APPROVED", "VERIFIED", "COMPLETED"].includes(value)) return "emerald";
  if (["PENDING", "UNDER_REVIEW", "IN_PROGRESS", "SUBMITTED"].includes(value)) return "amber";
  return "slate";
}

export default function PortalShell(props: { children: ReactNode }) {
  const [summary, setSummary] = useState<PortalSummary | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;

    async function load() {
      try {
        const data = await fetchPortalSummary();
        if (active) {
          setSummary(data);
        }
      } catch {
        if (active) {
          setSummary(null);
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    }

    load();
    return () => {
      active = false;
    };
  }, []);

  return (
    <>
      <div className="mx-auto max-w-[1500px] px-6 pt-6">
        <div className="rounded-[28px] border border-white/10 bg-[#0b1730] p-6 shadow-xl shadow-black/20">
          {loading ? (
            <div className="grid gap-4 md:grid-cols-4">
              {Array.from({ length: 4 }).map((_, idx) => (
                <div
                  key={idx}
                  className="h-20 animate-pulse rounded-[20px] border border-white/10 bg-white/[0.03]"
                />
              ))}
            </div>
          ) : summary ? (
            <div className="grid gap-4 xl:grid-cols-[1.4fr_1fr_1fr_1fr]">
              <div className="rounded-[22px] border border-white/10 bg-white/[0.02] p-5">
                <div className="text-sm uppercase tracking-[0.2em] text-slate-400">
                  Client
                </div>
                <div className="mt-2 text-2xl font-semibold text-slate-100">
                  {summary.displayName ?? "Client"}
                </div>
                <div className="mt-2 text-sm text-slate-300">
                  {summary.username ?? summary.email ?? "Authenticated session"}
                </div>
                <div className="mt-4 inline-flex items-center rounded-full border border-cyan-500/40 bg-cyan-500/10 px-3 py-1 text-xs font-semibold text-cyan-200">
                  {summary.userStatus ?? "ACTIVE"}
                </div>
              </div>

              <div className="rounded-[22px] border border-white/10 bg-white/[0.02] p-5">
                <div className="text-sm uppercase tracking-[0.2em] text-slate-400">
                  Onboarding
                </div>
                <div className="mt-2 text-2xl font-semibold text-slate-100">
                  {summary.onboarding.completionPercent}%
                </div>
                <div className="mt-2 text-sm text-slate-300">
                  {summary.onboarding.overallStatus ?? "Not started"}
                </div>
                <div className="mt-4 h-2 overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-cyan-400"
                    style={{ width: `${Math.max(0, Math.min(100, summary.onboarding.completionPercent))}%` }}
                  />
                </div>
              </div>

              <div className="rounded-[22px] border border-white/10 bg-white/[0.02] p-5">
                <div className="text-sm uppercase tracking-[0.2em] text-slate-400">
                  Verification / KYC
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  <span className={["inline-flex rounded-full border px-3 py-1 text-xs font-semibold", badgeClasses(summary.verification.emailVerified ? "emerald" : "amber")].join(" ")}>
                    Email {summary.verification.emailVerified ? "verified" : "pending"}
                  </span>
                  <span className={["inline-flex rounded-full border px-3 py-1 text-xs font-semibold", badgeClasses(summary.verification.phoneVerified ? "emerald" : "slate")].join(" ")}>
                    Phone {summary.verification.phoneVerified ? "verified" : "not set"}
                  </span>
                  <span className={["inline-flex rounded-full border px-3 py-1 text-xs font-semibold", badgeClasses(inferKycKind(summary.kyc.status))].join(" ")}>
                    KYC {summary.kyc.status ?? "not started"}
                  </span>
                </div>
                <div className="mt-3 text-sm text-slate-300">
                  Next step: {summary.onboarding.nextStepLabel ?? "Continue onboarding"}
                </div>
              </div>

              <div className="rounded-[22px] border border-white/10 bg-white/[0.02] p-5">
                <div className="text-sm uppercase tracking-[0.2em] text-slate-400">
                  Referral / Assets
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  {summary.referral.appliedCode ? (
                    <span className={["inline-flex rounded-full border px-3 py-1 text-xs font-semibold", badgeClasses("cyan")].join(" ")}>
                      Code {summary.referral.appliedCode}
                    </span>
                  ) : (
                    <span className={["inline-flex rounded-full border px-3 py-1 text-xs font-semibold", badgeClasses("slate")].join(" ")}>
                      No referral yet
                    </span>
                  )}

                  {summary.referral.pointsBalance != null ? (
                    <span className={["inline-flex rounded-full border px-3 py-1 text-xs font-semibold", badgeClasses("emerald")].join(" ")}>
                      {summary.referral.pointsBalance} pts
                    </span>
                  ) : null}
                </div>

                <div className="mt-3 text-sm text-slate-300">
                  {summary.portfolio.totalAssetValue
                    ? `Total asset value: ${summary.portfolio.totalAssetValue}`
                    : "Total asset value will appear here later."}
                </div>
              </div>
            </div>
          ) : (
            <div className="rounded-[20px] border border-white/10 bg-white/[0.03] px-5 py-4 text-sm text-slate-300">
              Client summary is temporarily unavailable.
            </div>
          )}
        </div>
      </div>

      {props.children}
    </>
  );
}
