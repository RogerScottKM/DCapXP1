#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

mkdir -p apps/web/src/lib
mkdir -p apps/web/src/features/auth
mkdir -p apps/web/pages

backup apps/web/package.json
backup apps/web/src/features/auth/RegisterPage.tsx
backup apps/web/pages/register.tsx

echo "==> Ensuring web dependency country-list ..."
node <<'NODE'
const fs = require("fs");
const path = "apps/web/package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
pkg.dependencies = pkg.dependencies || {};
if (!pkg.dependencies["country-list"]) {
  pkg.dependencies["country-list"] = "^2.4.1";
}
fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo "==> Writing country options helper ..."
cat > apps/web/src/lib/countries.ts <<'EOF'
import { getData } from "country-list";

export type CountryOption = {
  code: string;
  name: string;
};

export const COUNTRY_OPTIONS: CountryOption[] = getData()
  .map((item) => ({
    code: item.code.toUpperCase(),
    name: item.name,
  }))
  .sort((a, b) => a.name.localeCompare(b.name));

export function getCountryName(code: string): string {
  const normalized = code.trim().toUpperCase();
  return COUNTRY_OPTIONS.find((item) => item.code === normalized)?.name ?? normalized;
}
EOF

echo "==> Writing human-friendly API error mapper ..."
cat > apps/web/src/lib/humanizeApiError.ts <<'EOF'
function tryParseJsonString(input: string): unknown {
  try {
    return JSON.parse(input);
  } catch {
    return input;
  }
}

function flattenValidationMessage(input: unknown): string | null {
  if (typeof input === "string") {
    const parsed = tryParseJsonString(input);
    if (parsed !== input) return flattenValidationMessage(parsed);
    return input;
  }

  if (Array.isArray(input)) {
    const countryIssue = input.find(
      (item: any) =>
        item &&
        Array.isArray(item.path) &&
        item.path.includes("country")
    ) as any;

    if (countryIssue) {
      return "Please choose your country from the dropdown list.";
    }

    const firstMessage = input.find((item: any) => item?.message)?.message;
    if (typeof firstMessage === "string") {
      return firstMessage;
    }

    return null;
  }

  if (input && typeof input === "object") {
    const obj = input as Record<string, unknown>;

    if (typeof obj.message === "string") {
      const nested = flattenValidationMessage(obj.message);
      return nested ?? obj.message;
    }

    if (obj.error) {
      return flattenValidationMessage(obj.error);
    }
  }

  return null;
}

export function humanizeApiError(error: unknown): string {
  const fallback = "Something went wrong. Please try again.";

  if (!error) return fallback;

  if (typeof error === "string") {
    const lower = error.toLowerCase();

    if (lower.includes("network") || lower.includes("failed to fetch")) {
      return "We couldn’t reach the server. Please check your connection and try again.";
    }

    const parsed = flattenValidationMessage(error);
    if (parsed) {
      if (parsed.toLowerCase().includes("too big") && parsed.toLowerCase().includes("country")) {
        return "Please choose your country from the dropdown list.";
      }
      return parsed;
    }

    return error;
  }

  const anyErr = error as any;

  const code = anyErr?.error?.code ?? anyErr?.code;
  const message = anyErr?.error?.message ?? anyErr?.message;

  if (code === "EMAIL_ALREADY_EXISTS") {
    return "That email address is already registered. Try signing in or resetting your password.";
  }

  if (code === "USERNAME_ALREADY_EXISTS") {
    return "That username is already taken. Please choose another one.";
  }

  if (typeof message === "string") {
    const parsed = flattenValidationMessage(message);
    if (parsed) {
      if (parsed.toLowerCase().includes("too big") && parsed.toLowerCase().includes("country")) {
        return "Please choose your country from the dropdown list.";
      }
      return parsed;
    }
  }

  const flattened = flattenValidationMessage(error);
  if (flattened) {
    if (flattened.toLowerCase().includes("too big") && flattened.toLowerCase().includes("country")) {
      return "Please choose your country from the dropdown list.";
    }
    return flattened;
  }

  return fallback;
}
EOF

echo "==> Rewriting RegisterPage.tsx ..."
cat > apps/web/src/features/auth/RegisterPage.tsx <<'EOF'
import Link from "next/link";
import { FormEvent, useMemo, useState } from "react";
import { COUNTRY_OPTIONS } from "../../lib/countries";
import { humanizeApiError } from "../../lib/humanizeApiError";

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
    <div className="min-h-screen bg-[#020817] text-white">
      <div className="mx-auto max-w-[1600px] px-6 py-8">
        <div className="flex items-center justify-between border-b border-white/10 pb-6">
          <Link href="/" className="text-4xl font-semibold tracking-tight">
            DCapX
          </Link>
          <div className="flex items-center gap-8 text-xl text-slate-300">
            <Link href="/foundation" className="hover:text-white">Foundation</Link>
            <Link href="/agent-advisory" className="hover:text-white">Agent Advisory</Link>
            <Link href="/dashboard" className="hover:text-white">Dashboard</Link>
            <Link href="/exchange" className="hover:text-white">Exchange</Link>
            <Link href="/portfolio" className="hover:text-white">Portfolio</Link>
            <Link href="/account" className="hover:text-white">Account</Link>
          </div>
        </div>

        <div className="grid gap-10 pt-10 lg:grid-cols-[1.1fr_0.9fr]">
          <div className="flex flex-col justify-center">
            <div className="mb-8 inline-flex w-fit items-center rounded-full border border-cyan-400/40 bg-cyan-500/10 px-5 py-2 text-xl font-semibold text-cyan-300">
              Join the Agent-Native Economy
            </div>

            <h1 className="max-w-4xl text-7xl font-semibold leading-[1.02] tracking-tight text-slate-100">
              Create your DCapX account and start your onboarding journey.
            </h1>

            <p className="mt-8 max-w-4xl text-2xl leading-relaxed text-slate-300">
              Set up your account details, optionally add a referral code, and we will send you a
              secure password setup link as the next step.
            </p>

            <div className="mt-10 grid gap-6 md:grid-cols-3">
              <div className="rounded-[28px] border border-white/10 bg-white/[0.03] p-7">
                <h3 className="text-3xl font-semibold">Growth-ready</h3>
                <p className="mt-3 text-xl leading-relaxed text-slate-300">
                  Referral-aware onboarding from day one.
                </p>
              </div>

              <div className="rounded-[28px] border border-white/10 bg-white/[0.03] p-7">
                <h3 className="text-3xl font-semibold">Compliance-first</h3>
                <p className="mt-3 text-xl leading-relaxed text-slate-300">
                  Identity, KYC, and consent flow stay controlled.
                </p>
              </div>

              <div className="rounded-[28px] border border-white/10 bg-white/[0.03] p-7">
                <h3 className="text-3xl font-semibold">Future-proof</h3>
                <p className="mt-3 text-xl leading-relaxed text-slate-300">
                  Referral rewards can later expand into points, cash, or tokens.
                </p>
              </div>
            </div>
          </div>

          <div className="rounded-[36px] border border-white/10 bg-[#0b1730] p-10 shadow-2xl shadow-black/25">
            <h2 className="text-5xl font-semibold tracking-tight">Create account</h2>
            <p className="mt-4 text-2xl leading-relaxed text-slate-300">
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
                  label="First name"
                  value={form.firstName}
                  onChange={(value) => setForm((prev) => ({ ...prev, firstName: value }))}
                  autoComplete="given-name"
                />
                <Field
                  label="Last name"
                  value={form.lastName}
                  onChange={(value) => setForm((prev) => ({ ...prev, lastName: value }))}
                  autoComplete="family-name"
                />
              </div>

              <div className="grid gap-6 md:grid-cols-2">
                <Field
                  label="Email"
                  type="email"
                  value={form.email}
                  onChange={(value) => setForm((prev) => ({ ...prev, email: value }))}
                  autoComplete="email"
                />
                <Field
                  label="Phone"
                  value={form.phone}
                  onChange={(value) => setForm((prev) => ({ ...prev, phone: value }))}
                  autoComplete="tel"
                />
              </div>

              <div className="grid gap-6 md:grid-cols-2">
                <Field
                  label="Username"
                  value={form.username}
                  onChange={(value) => setForm((prev) => ({ ...prev, username: value }))}
                  autoComplete="username"
                />

                <div>
                  <label className="mb-3 block text-2xl font-semibold text-white">Country</label>
                  <select
                    value={form.country}
                    onChange={(e) => setForm((prev) => ({ ...prev, country: e.target.value }))}
                    className="w-full rounded-[22px] border border-white/10 bg-[#020817] px-6 py-5 text-2xl text-white outline-none transition focus:border-cyan-400"
                  >
                    {COUNTRY_OPTIONS.map((country) => (
                      <option key={country.code} value={country.code}>
                        {country.name} ({country.code})
                      </option>
                    ))}
                  </select>
                  <p className="mt-3 text-lg text-slate-400">
                    Stored as ISO country code: <span className="font-semibold text-slate-200">{selectedCountry?.code}</span>
                    {" · "}
                    {selectedCountry?.name}
                  </p>
                </div>
              </div>

              <div>
                <Field
                  label="Referral code (optional)"
                  value={form.referralCode}
                  onChange={(value) => setForm((prev) => ({ ...prev, referralCode: value }))}
                />
                <p className="mt-3 text-lg text-slate-400">
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

              <p className="text-xl text-slate-300">
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
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
  autoComplete?: string;
}) {
  return (
    <div>
      <label className="mb-3 block text-2xl font-semibold text-white">{props.label}</label>
      <input
        type={props.type ?? "text"}
        value={props.value}
        autoComplete={props.autoComplete}
        onChange={(e) => props.onChange(e.target.value)}
        className="w-full rounded-[22px] border border-white/10 bg-[#020817] px-6 py-5 text-2xl text-white outline-none transition placeholder:text-slate-500 focus:border-cyan-400"
      />
    </div>
  );
}
EOF

echo "==> Rewriting register page route ..."
cat > apps/web/pages/register.tsx <<'EOF'
import RegisterPage from "../src/features/auth/RegisterPage";

export default RegisterPage;
EOF

echo "==> Installing deps ..."
pnpm install

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Register UX improvement pack applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
echo
echo "What changed:"
echo "  - country is now selected from a dropdown"
echo "  - database receives ISO alpha-2 code directly"
echo "  - country validation errors are now client-friendly"
