#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

mkdir -p apps/web/src/lib/preferences
mkdir -p apps/web/src/components/portal
mkdir -p apps/web/pages
mkdir -p apps/web/src/features/auth

backup apps/web/pages/_app.tsx
backup apps/web/src/components/portal/ThemeToggle.tsx
backup apps/web/src/features/auth/RegisterPage.tsx

echo "==> Writing shared preferences provider (.tsx, not .ts) ..."
cat > apps/web/src/lib/preferences/PortalPreferencesProvider.tsx <<'EOF'
import React, {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type PortalTheme = "dark" | "light";

export const PORTAL_LANGUAGES = [
  { code: "en", label: "English" },
  { code: "vi", label: "Tiếng Việt" },
  { code: "zh-CN", label: "简体中文" },
  { code: "zh-TW", label: "繁體中文" },
  { code: "es", label: "Español" },
  { code: "fr", label: "Français" },
  { code: "ar", label: "العربية" },
  { code: "pt", label: "Português" },
  { code: "hi", label: "हिन्दी" },
  { code: "ja", label: "日本語" },
] as const;

export type PortalLanguageCode = (typeof PORTAL_LANGUAGES)[number]["code"];

type PortalPreferencesContextValue = {
  theme: PortalTheme;
  isDark: boolean;
  isLight: boolean;
  language: PortalLanguageCode;
  mounted: boolean;
  setTheme: (theme: PortalTheme) => void;
  toggleTheme: () => void;
  setLanguage: (language: PortalLanguageCode) => void;
};

const THEME_KEY = "dcapx-theme";
const LANGUAGE_KEY = "dcapx-language";

const PortalPreferencesContext =
  createContext<PortalPreferencesContextValue | null>(null);

export function PortalPreferencesProvider(props: { children: ReactNode }) {
  const [theme, setTheme] = useState<PortalTheme>("dark");
  const [language, setLanguage] = useState<PortalLanguageCode>("en");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    try {
      const storedTheme =
        typeof window !== "undefined" ? window.localStorage.getItem(THEME_KEY) : null;
      const storedLanguage =
        typeof window !== "undefined" ? window.localStorage.getItem(LANGUAGE_KEY) : null;

      if (storedTheme === "dark" || storedTheme === "light") {
        setTheme(storedTheme);
      } else {
        const prefersDark =
          typeof window !== "undefined" &&
          typeof window.matchMedia === "function" &&
          window.matchMedia("(prefers-color-scheme: dark)").matches;
        setTheme(prefersDark ? "dark" : "light");
      }

      if (
        storedLanguage &&
        PORTAL_LANGUAGES.some((item) => item.code === storedLanguage)
      ) {
        setLanguage(storedLanguage as PortalLanguageCode);
      }
    } finally {
      setMounted(true);
    }
  }, []);

  useEffect(() => {
    if (!mounted || typeof document === "undefined") return;

    document.documentElement.dataset.dcapxTheme = theme;
    document.documentElement.dataset.dcapxLanguage = language;

    document.documentElement.classList.remove("dcapx-dark", "dcapx-light");
    document.documentElement.classList.add(
      theme === "dark" ? "dcapx-dark" : "dcapx-light"
    );

    document.body.style.backgroundColor =
      theme === "dark" ? "#020817" : "#e5e7eb";
    document.body.style.color = theme === "dark" ? "#ffffff" : "#0f172a";

    if (typeof window !== "undefined") {
      window.localStorage.setItem(THEME_KEY, theme);
      window.localStorage.setItem(LANGUAGE_KEY, language);
    }
  }, [theme, language, mounted]);

  const value = useMemo<PortalPreferencesContextValue>(
    () => ({
      theme,
      isDark: theme === "dark",
      isLight: theme === "light",
      language,
      mounted,
      setTheme,
      toggleTheme: () =>
        setTheme((prev) => (prev === "dark" ? "light" : "dark")),
      setLanguage,
    }),
    [theme, language, mounted]
  );

  return (
    <PortalPreferencesContext.Provider value={value}>
      {props.children}
    </PortalPreferencesContext.Provider>
  );
}

export function usePortalPreferences() {
  const context = useContext(PortalPreferencesContext);

  if (!context) {
    throw new Error(
      "usePortalPreferences must be used within PortalPreferencesProvider"
    );
  }

  return context;
}
EOF

echo "==> Writing shared ThemeToggle ..."
cat > apps/web/src/components/portal/ThemeToggle.tsx <<'EOF'
import { usePortalPreferences } from "../../lib/preferences/PortalPreferencesProvider";

export default function ThemeToggle() {
  const { isDark, toggleTheme, mounted } = usePortalPreferences();

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

echo "==> Writing language selector ..."
cat > apps/web/src/components/portal/LanguageSelect.tsx <<'EOF'
import {
  PORTAL_LANGUAGES,
  usePortalPreferences,
} from "../../lib/preferences/PortalPreferencesProvider";

export default function LanguageSelect() {
  const { language, setLanguage, isDark } = usePortalPreferences();

  return (
    <label
      className={[
        "inline-flex items-center gap-2 rounded-full border px-3 py-2 text-sm font-semibold transition",
        isDark
          ? "border-white/10 bg-white/[0.04] text-slate-100"
          : "border-slate-300 bg-white text-slate-900",
      ].join(" ")}
    >
      <span>🌐</span>
      <select
        value={language}
        onChange={(e) => setLanguage(e.target.value as any)}
        className={[
          "bg-transparent outline-none",
          isDark ? "text-slate-100" : "text-slate-900",
        ].join(" ")}
        aria-label="Select language"
      >
        {PORTAL_LANGUAGES.map((item) => (
          <option key={item.code} value={item.code}>
            {item.label}
          </option>
        ))}
      </select>
    </label>
  );
}
EOF

echo "==> Writing _app.tsx ..."
cat > apps/web/pages/_app.tsx <<'EOF'
import type { AppProps } from "next/app";
import { PortalPreferencesProvider } from "../src/lib/preferences/PortalPreferencesProvider";

export default function App({ Component, pageProps }: AppProps) {
  return (
    <PortalPreferencesProvider>
      <Component {...pageProps} />
    </PortalPreferencesProvider>
  );
}
EOF

echo "==> Rewriting RegisterPage.tsx ..."
cat > apps/web/src/features/auth/RegisterPage.tsx <<'EOF'
import Link from "next/link";
import { FormEvent, useMemo, useState } from "react";
import ThemeToggle from "../../components/portal/ThemeToggle";
import LanguageSelect from "../../components/portal/LanguageSelect";
import { COUNTRY_OPTIONS } from "../../lib/countries";
import { humanizeApiError } from "../../lib/humanizeApiError";
import { usePortalPreferences } from "../../lib/preferences/PortalPreferencesProvider";

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
        if (res.status !== 404) throw lastError;
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
  const { isDark } = usePortalPreferences();

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

  const pageClass = isDark ? "bg-[#020817] text-white" : "bg-[#e5e7eb] text-slate-900";
  const borderClass = isDark ? "border-white/10" : "border-slate-300";
  const panelClass = isDark ? "bg-[#0b1730]" : "bg-[#f8fafc]";
  const subTextClass = isDark ? "text-slate-300" : "text-slate-700";
  const statCardClass = isDark ? "bg-white/[0.03]" : "bg-[#f1f5f9]";
  const badgeClass = isDark
    ? "border-cyan-400/40 bg-cyan-500/10 text-cyan-300"
    : "border-cyan-500/50 bg-cyan-50 text-cyan-800";
  const inputClass = isDark
    ? "border-white/10 bg-[#020817] text-white placeholder:text-slate-500 focus:border-cyan-400"
    : "border-slate-300 bg-white text-slate-900 placeholder:text-slate-400 focus:border-cyan-500";

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
    } catch (error) {
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

          <div className={`flex items-center gap-6 text-xl ${subTextClass}`}>
            <Link href="/foundation" className="hover:text-inherit">Foundation</Link>
            <Link href="/agent-advisory" className="hover:text-inherit">Agent Advisory</Link>
            <Link href="/dashboard" className="hover:text-inherit">Dashboard</Link>
            <Link href="/exchange" className="hover:text-inherit">Exchange</Link>
            <Link href="/portfolio" className="hover:text-inherit">Portfolio</Link>
            <Link href="/account" className="hover:text-inherit">Account</Link>
            <LanguageSelect />
            <ThemeToggle />
          </div>
        </div>

        <div className="grid gap-10 pt-10 lg:grid-cols-[1.1fr_0.9fr]">
          <div className="flex flex-col justify-center">
            <div className={`mb-8 inline-flex w-fit items-center rounded-full border px-5 py-2 text-xl font-semibold ${badgeClass}`}>
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
                <Field dark={isDark} label="First name" value={form.firstName} onChange={(value) => setForm((prev) => ({ ...prev, firstName: value }))} />
                <Field dark={isDark} label="Last name" value={form.lastName} onChange={(value) => setForm((prev) => ({ ...prev, lastName: value }))} />
              </div>

              <div className="grid gap-6 md:grid-cols-2">
                <Field dark={isDark} label="Email" type="email" value={form.email} onChange={(value) => setForm((prev) => ({ ...prev, email: value }))} />
                <Field dark={isDark} label="Phone" value={form.phone} onChange={(value) => setForm((prev) => ({ ...prev, phone: value }))} />
              </div>

              <div className="grid gap-6 md:grid-cols-2">
                <Field dark={isDark} label="Username" value={form.username} onChange={(value) => setForm((prev) => ({ ...prev, username: value }))} />

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
                    <span className={isDark ? "font-semibold text-cyan-300" : "font-semibold text-cyan-700"}>
                      {selectedCountry?.code}
                    </span>
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
                <Link href="/login" className={isDark ? "font-semibold text-cyan-300 hover:text-cyan-200" : "font-semibold text-cyan-700 hover:text-cyan-800"}>
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

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Theme + language selector fix applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
