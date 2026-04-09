#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

mkdir -p apps/web/src/components/portal
mkdir -p apps/web/src/lib/api
mkdir -p apps/web/src/lib/theme
mkdir -p apps/web/pages/api/me
mkdir -p apps/web/pages/app

backup apps/web/src/features/auth/RegisterPage.tsx
backup apps/web/pages/register.tsx
backup apps/web/pages/app/onboarding.tsx
backup apps/web/pages/app/verify-contact.tsx
backup apps/web/pages/app/consents.tsx
backup apps/web/pages/app/kyc.tsx

echo "==> Writing theme hook ..."
cat > apps/web/src/lib/theme/usePortalTheme.ts <<'EOF'
import { useEffect, useMemo, useState } from "react";

export type PortalTheme = "dark" | "light";

const STORAGE_KEY = "dcapx-theme";

export function usePortalTheme() {
  const [theme, setTheme] = useState<PortalTheme>("dark");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(STORAGE_KEY);
      if (stored === "dark" || stored === "light") {
        setTheme(stored);
      } else {
        const prefersDark =
          typeof window !== "undefined" &&
          window.matchMedia &&
          window.matchMedia("(prefers-color-scheme: dark)").matches;
        setTheme(prefersDark ? "dark" : "light");
      }
    } finally {
      setMounted(true);
    }
  }, []);

  useEffect(() => {
    if (!mounted) return;
    window.localStorage.setItem(STORAGE_KEY, theme);
    document.documentElement.dataset.dcapxTheme = theme;
  }, [mounted, theme]);

  const toggleTheme = () => {
    setTheme((prev) => (prev === "dark" ? "light" : "dark"));
  };

  return useMemo(
    () => ({
      theme,
      isDark: theme === "dark",
      isLight: theme === "light",
      mounted,
      setTheme,
      toggleTheme,
    }),
    [theme, mounted]
  );
}
EOF

echo "==> Writing theme toggle component ..."
cat > apps/web/src/components/portal/ThemeToggle.tsx <<'EOF'
import { usePortalTheme } from "../../lib/theme/usePortalTheme";

export default function ThemeToggle() {
  const { isDark, toggleTheme, mounted } = usePortalTheme();

  return (
    <button
      type="button"
      onClick={toggleTheme}
      className={[
        "inline-flex items-center gap-2 rounded-full border px-4 py-2 text-base font-semibold transition",
        isDark
          ? "border-white/10 bg-white/[0.04] text-slate-100 hover:bg-white/[0.07]"
          : "border-slate-300 bg-white text-slate-900 hover:bg-slate-50",
      ].join(" ")}
      aria-label="Toggle theme"
      title="Toggle theme"
    >
      <span>{isDark ? "🌙" : "☀️"}</span>
      <span>{mounted ? (isDark ? "Dark" : "Light") : "Theme"}</span>
    </button>
  );
}
EOF

echo "==> Writing portal summary client helper ..."
cat > apps/web/src/lib/api/portalSummary.ts <<'EOF'
export type PortalSummary = {
  displayName: string | null;
  username: string | null;
  email: string | null;
  userStatus: string | null;
  onboarding: {
    overallStatus: string | null;
    completionPercent: number;
    nextStepLabel: string | null;
  };
  verification: {
    emailVerified: boolean;
    phoneVerified: boolean;
  };
  kyc: {
    status: string | null;
  };
  referral: {
    appliedCode: string | null;
    attributionStatus: string | null;
    pointsBalance: number | null;
  };
  portfolio: {
    totalAssetValue: string | null;
  };
};

export async function fetchPortalSummary(): Promise<PortalSummary> {
  const res = await fetch("/api/me/portal-summary", {
    credentials: "include",
    headers: {
      Accept: "application/json",
    },
  });

  const raw = await res.text();
  let data: any = null;

  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = raw;
  }

  if (!res.ok) {
    throw data ?? { message: `Request failed with status ${res.status}.` };
  }

  return data as PortalSummary;
}
EOF

echo "==> Writing portal summary BFF endpoint ..."
cat > apps/web/pages/api/me/portal-summary.ts <<'EOF'
import type { NextApiRequest, NextApiResponse } from "next";

type UpstreamResult = {
  ok: boolean;
  status: number;
  data: any;
};

function getApiBase(): string {
  return process.env.API_INTERNAL_URL ?? "http://api:4010";
}

async function fetchUpstream(
  req: NextApiRequest,
  pathCandidates: string[]
): Promise<UpstreamResult> {
  const base = getApiBase().replace(/\/+$/, "");
  const cookie = req.headers.cookie ?? "";

  let last: UpstreamResult = {
    ok: false,
    status: 404,
    data: null,
  };

  for (const path of pathCandidates) {
    const url = `${base}${path}`;
    try {
      const response = await fetch(url, {
        method: "GET",
        headers: {
          Accept: "application/json",
          ...(cookie ? { cookie } : {}),
        },
      });

      const raw = await response.text();
      let data: any = null;
      try {
        data = raw ? JSON.parse(raw) : null;
      } catch {
        data = raw;
      }

      const result: UpstreamResult = {
        ok: response.ok,
        status: response.status,
        data,
      };

      if (response.ok || response.status === 401 || response.status === 403) {
        return result;
      }

      last = result;
    } catch (error: any) {
      last = {
        ok: false,
        status: 500,
        data: {
          error: {
            message: error?.message ?? "Upstream request failed.",
          },
        },
      };
    }
  }

  return last;
}

function pickUser(sessionData: any) {
  return (
    sessionData?.user ??
    sessionData?.session?.user ??
    sessionData?.data?.user ??
    null
  );
}

function pickDisplayName(user: any): string | null {
  if (!user) return null;
  if (user.displayName) return String(user.displayName);
  if (user.name) return String(user.name);

  const firstName = user.firstName ?? user.first_name ?? null;
  const lastName = user.lastName ?? user.last_name ?? null;

  if (firstName || lastName) {
    return [firstName, lastName].filter(Boolean).join(" ");
  }

  return user.username ?? user.email ?? null;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const session = await fetchUpstream(req, [
    "/api/auth/session",
    "/backend-api/auth/session",
    "/auth/session",
  ]);

  if (session.status === 401 || session.status === 403 || !session.ok) {
    return res.status(401).json({
      error: {
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      },
    });
  }

  const user = pickUser(session.data);

  const onboarding = await fetchUpstream(req, [
    "/api/me/onboarding-status",
    "/backend-api/me/onboarding-status",
    "/me/onboarding-status",
  ]);

  const kyc = await fetchUpstream(req, [
    "/api/me/kyc-case",
    "/backend-api/me/kyc-case",
    "/me/kyc-case",
  ]);

  const referral = await fetchUpstream(req, [
    "/api/me/referral-status",
    "/backend-api/me/referral-status",
    "/me/referral-status",
  ]);

  const onboardingData = onboarding.ok ? onboarding.data : null;
  const kycData = kyc.ok ? kyc.data : null;
  const referralData = referral.ok ? referral.data : null;

  const kycStatus =
    kycData?.status ??
    onboardingData?.entities?.kycCase?.status ??
    null;

  const payload = {
    displayName: pickDisplayName(user),
    username: user?.username ?? null,
    email: user?.email ?? null,
    userStatus: user?.status ?? onboardingData?.overallStatus ?? null,
    onboarding: {
      overallStatus: onboardingData?.overallStatus ?? null,
      completionPercent: Number(onboardingData?.completionPercent ?? 0),
      nextStepLabel:
        onboardingData?.nextRecommendedAction?.label ??
        onboardingData?.currentStep ??
        null,
    },
    verification: {
      emailVerified: Boolean(user?.emailVerifiedAt),
      phoneVerified: Boolean(user?.phoneVerifiedAt),
    },
    kyc: {
      status: kycStatus,
    },
    referral: {
      appliedCode:
        referralData?.appliedCode ??
        onboardingData?.entities?.referral?.appliedCode ??
        null,
      attributionStatus:
        referralData?.attributionStatus ??
        onboardingData?.entities?.referral?.attributionStatus ??
        null,
      pointsBalance:
        typeof referralData?.pointsBalance === "number"
          ? referralData.pointsBalance
          : typeof onboardingData?.entities?.referral?.pointsBalance === "number"
            ? onboardingData.entities.referral.pointsBalance
            : null,
    },
    portfolio: {
      totalAssetValue: null,
    },
  };

  return res.status(200).json(payload);
}
EOF

echo "==> Writing portal shell ..."
cat > apps/web/src/components/portal/PortalShell.tsx <<'EOF'
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
EOF

echo "==> Rewriting /register with theme toggle ..."
cat > apps/web/src/features/auth/RegisterPage.tsx <<'EOF'
import Link from "next/link";
import { FormEvent, useMemo, useState } from "react";
import ThemeToggle from "../../components/portal/ThemeToggle";
import { COUNTRY_OPTIONS } from "../../lib/countries";
import { humanizeApiError } from "../../lib/humanizeApiError";
import { usePortalTheme } from "../../lib/theme/usePortalTheme";

type RegisterPayload = {
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  username: string;
  country: string;
  referralCode?: string;
};

async function postRegister(payload: RegisterPayload) {
  const body = JSON.stringify(payload);
  const endpoints = ["/backend-api/auth/register", "/api/auth/register"];

  let lastError: unknown = null;

  for (const endpoint of endpoints) {
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        credentials: "include",
      });

      const raw = await res.text();
      let data: any = null;
      try {
        data = raw ? JSON.parse(raw) : null;
      } catch {
        data = raw;
      }

      if (!res.ok) {
        lastError = data ?? raw ?? `Request failed with status ${res.status}`;
        if (res.status !== 404) {
          throw lastError;
        }
        continue;
      }

      return data;
    } catch (error) {
      lastError = error;
      if (String(error).includes("404")) continue;
      throw error;
    }
  }

  throw lastError ?? new Error("Registration endpoint not found.");
}

export default function RegisterPage() {
  const { isDark } = usePortalTheme();

  const [form, setForm] = useState({
    firstName: "",
    lastName: "",
    email: "",
    phone: "",
    username: "",
    country: "AU",
    referralCode: "",
  });

  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [successMessage, setSuccessMessage] = useState("");

  const selectedCountry = useMemo(
    () => COUNTRY_OPTIONS.find((item) => item.code === form.country),
    [form.country]
  );

  const pageClass = isDark ? "bg-[#020817] text-white" : "bg-slate-100 text-slate-900";
  const borderClass = isDark ? "border-white/10" : "border-slate-300";
  const panelClass = isDark ? "bg-[#0b1730]" : "bg-white";
  const subTextClass = isDark ? "text-slate-300" : "text-slate-600";
  const inputClass = isDark
    ? "border-white/10 bg-[#020817] text-white placeholder:text-slate-500 focus:border-cyan-400"
    : "border-slate-300 bg-white text-slate-900 placeholder:text-slate-400 focus:border-cyan-500";
  const statCardClass = isDark ? "bg-white/[0.03]" : "bg-slate-50";

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setErrorMessage("");
    setSuccessMessage("");

    try {
      await postRegister({
        firstName: form.firstName.trim(),
        lastName: form.lastName.trim(),
        email: form.email.trim().toLowerCase(),
        phone: form.phone.trim(),
        username: form.username.trim(),
        country: form.country.trim().toUpperCase(),
        referralCode: form.referralCode.trim() || undefined,
      });

      setSuccessMessage(
        "Account created successfully. Next, use the password setup link to secure your account."
      );

      setForm({
        firstName: "",
        lastName: "",
        email: "",
        phone: "",
        username: "",
        country: "AU",
        referralCode: "",
      });
    } catch (error: any) {
      setErrorMessage(humanizeApiError(error));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className={`min-h-screen ${pageClass}`}>
      <div className="mx-auto max-w-[1600px] px-6 py-8">
        <div className={`flex items-center justify-between border-b ${borderClass} pb-6`}>
          <Link href="/" className="text-4xl font-semibold tracking-tight">
            DCapX
          </Link>

          <div className={`flex items-center gap-8 text-xl ${subTextClass}`}>
            <Link href="/foundation" className="hover:text-inherit">Foundation</Link>
            <Link href="/agent-advisory" className="hover:text-inherit">Agent Advisory</Link>
            <Link href="/dashboard" className="hover:text-inherit">Dashboard</Link>
            <Link href="/exchange" className="hover:text-inherit">Exchange</Link>
            <Link href="/portfolio" className="hover:text-inherit">Portfolio</Link>
            <Link href="/account" className="hover:text-inherit">Account</Link>
            <ThemeToggle />
          </div>
        </div>

        <div className="grid gap-10 pt-10 lg:grid-cols-[1.1fr_0.9fr]">
          <div className="flex flex-col justify-center">
            <div className="mb-8 inline-flex w-fit items-center rounded-full border border-cyan-400/40 bg-cyan-500/10 px-5 py-2 text-xl font-semibold text-cyan-300">
              Join the Agent-Native Economy
            </div>

            <h1 className="max-w-4xl text-7xl font-semibold leading-[1.02] tracking-tight">
              Create your DCapX account and start your onboarding journey.
            </h1>

            <p className={`mt-8 max-w-4xl text-2xl leading-relaxed ${subTextClass}`}>
              Set up your account details, optionally add a referral code, and we will send you a
              secure password setup link as the next step.
            </p>

            <div className="mt-10 grid gap-6 md:grid-cols-3">
              <div className={`rounded-[28px] border ${borderClass} ${statCardClass} p-7`}>
                <h3 className="text-3xl font-semibold">Growth-ready</h3>
                <p className={`mt-3 text-xl leading-relaxed ${subTextClass}`}>
                  Referral-aware onboarding from day one.
                </p>
              </div>

              <div className={`rounded-[28px] border ${borderClass} ${statCardClass} p-7`}>
                <h3 className="text-3xl font-semibold">Compliance-first</h3>
                <p className={`mt-3 text-xl leading-relaxed ${subTextClass}`}>
                  Identity, KYC, and consent flow stay controlled.
                </p>
              </div>

              <div className={`rounded-[28px] border ${borderClass} ${statCardClass} p-7`}>
                <h3 className="text-3xl font-semibold">Future-proof</h3>
                <p className={`mt-3 text-xl leading-relaxed ${subTextClass}`}>
                  Referral rewards can later expand into points, cash, or tokens.
                </p>
              </div>
            </div>
          </div>

          <div className={`rounded-[36px] border ${borderClass} ${panelClass} p-10 shadow-2xl shadow-black/25`}>
            <h2 className="text-5xl font-semibold tracking-tight">Create account</h2>
            <p className={`mt-4 text-2xl leading-relaxed ${subTextClass}`}>
              New clients start here. We’ll send a password setup link after account creation.
            </p>

            {errorMessage ? (
              <div className="mt-8 rounded-[24px] border border-rose-500/40 bg-rose-500/10 px-6 py-5 text-xl leading-relaxed text-rose-100">
                <span className="font-semibold">Error:</span> {errorMessage}
              </div>
            ) : null}

            {successMessage ? (
              <div className="mt-8 rounded-[24px] border border-emerald-500/40 bg-emerald-500/10 px-6 py-5 text-xl leading-relaxed text-emerald-100">
                <span className="font-semibold">Success:</span> {successMessage}
              </div>
            ) : null}

            <form onSubmit={onSubmit} className="mt-10 space-y-7">
              <div className="grid gap-6 md:grid-cols-2">
                <Field
                  dark={isDark}
                  label="First name"
                  value={form.firstName}
                  onChange={(value) => setForm((prev) => ({ ...prev, firstName: value }))}
                />
                <Field
                  dark={isDark}
                  label="Last name"
                  value={form.lastName}
                  onChange={(value) => setForm((prev) => ({ ...prev, lastName: value }))}
                />
              </div>

              <div className="grid gap-6 md:grid-cols-2">
                <Field
                  dark={isDark}
                  label="Email"
                  type="email"
                  value={form.email}
                  onChange={(value) => setForm((prev) => ({ ...prev, email: value }))}
                />
                <Field
                  dark={isDark}
                  label="Phone"
                  value={form.phone}
                  onChange={(value) => setForm((prev) => ({ ...prev, phone: value }))}
                />
              </div>

              <div className="grid gap-6 md:grid-cols-2">
                <Field
                  dark={isDark}
                  label="Username"
                  value={form.username}
                  onChange={(value) => setForm((prev) => ({ ...prev, username: value }))}
                />

                <div>
                  <label className="mb-3 block text-2xl font-semibold">Country</label>
                  <select
                    value={form.country}
                    onChange={(e) => setForm((prev) => ({ ...prev, country: e.target.value }))}
                    className={[
                      "w-full rounded-[22px] border px-6 py-5 text-2xl outline-none transition",
                      inputClass,
                    ].join(" ")}
                  >
                    {COUNTRY_OPTIONS.map((country) => (
                      <option key={country.code} value={country.code}>
                        {country.name} ({country.code})
                      </option>
                    ))}
                  </select>
                  <p className={`mt-3 text-lg ${subTextClass}`}>
                    Stored as ISO country code:{" "}
                    <span className="font-semibold text-cyan-300">{selectedCountry?.code}</span>
                    {" · "}
                    {selectedCountry?.name}
                  </p>
                </div>
              </div>

              <div>
                <Field
                  dark={isDark}
                  label="Referral code (optional)"
                  value={form.referralCode}
                  onChange={(value) => setForm((prev) => ({ ...prev, referralCode: value }))}
                />
                <p className={`mt-3 text-lg ${subTextClass}`}>
                  We’ll save this code and make it available during your first onboarding session.
                </p>
              </div>

              <button
                type="submit"
                disabled={submitting}
                className="w-full rounded-[24px] border border-cyan-400/50 bg-cyan-500/20 px-6 py-5 text-3xl font-semibold text-cyan-100 transition hover:bg-cyan-500/30 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {submitting ? "Creating account..." : "Create Account"}
              </button>

              <p className={`text-xl ${subTextClass}`}>
                Already have an account?{" "}
                <Link href="/login" className="font-semibold text-cyan-300 hover:text-cyan-200">
                  Log in
                </Link>
              </p>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}

function Field(props: {
  dark: boolean;
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
}) {
  const inputClass = props.dark
    ? "border-white/10 bg-[#020817] text-white placeholder:text-slate-500 focus:border-cyan-400"
    : "border-slate-300 bg-white text-slate-900 placeholder:text-slate-400 focus:border-cyan-500";

  return (
    <div>
      <label className="mb-3 block text-2xl font-semibold">{props.label}</label>
      <input
        type={props.type ?? "text"}
        value={props.value}
        onChange={(e) => props.onChange(e.target.value)}
        className={[
          "w-full rounded-[22px] border px-6 py-5 text-2xl outline-none transition",
          inputClass,
        ].join(" ")}
      />
    </div>
  );
}
EOF

echo "==> Writing /register page ..."
cat > apps/web/pages/register.tsx <<'EOF'
import RegisterPage from "../src/features/auth/RegisterPage";

export default RegisterPage;
EOF

echo "==> Wrapping protected routes with PortalShell ..."
cat > apps/web/pages/app/onboarding.tsx <<'EOF'
import PortalShell from "../../src/components/portal/PortalShell";
import OnboardingPage from "../../src/features/onboarding/OnboardingPage";

export default function OnboardingRoute() {
  return (
    <PortalShell>
      <OnboardingPage />
    </PortalShell>
  );
}
EOF

cat > apps/web/pages/app/verify-contact.tsx <<'EOF'
import PortalShell from "../../src/components/portal/PortalShell";
import VerifyContactPage from "../../src/features/onboarding/VerifyContactPage";

export default function VerifyContactRoute() {
  return (
    <PortalShell>
      <VerifyContactPage />
    </PortalShell>
  );
}
EOF

cat > apps/web/pages/app/consents.tsx <<'EOF'
import PortalShell from "../../src/components/portal/PortalShell";
import ConsentsPage from "../../src/features/onboarding/ConsentsPage";

export default function ConsentsRoute() {
  return (
    <PortalShell>
      <ConsentsPage />
    </PortalShell>
  );
}
EOF

cat > apps/web/pages/app/kyc.tsx <<'EOF'
import PortalShell from "../../src/components/portal/PortalShell";
import KycPage from "../../src/features/onboarding/KycPage";

export default function KycRoute() {
  return (
    <PortalShell>
      <KycPage />
    </PortalShell>
  );
}
EOF

echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ PortalShell + register theme pack applied."
echo
echo "What changed:"
echo "  - /api/me/portal-summary added as single BFF endpoint"
echo "  - PortalShell added with shared authenticated client strip"
echo "  - /app/onboarding wrapped"
echo "  - /app/verify-contact wrapped"
echo "  - /app/consents wrapped"
echo "  - /app/kyc wrapped"
echo "  - /register now has dark/light switch"
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
