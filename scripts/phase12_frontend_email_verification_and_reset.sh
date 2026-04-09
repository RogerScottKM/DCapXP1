#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

mkdir -p apps/web/src/lib/api
mkdir -p apps/web/src/features/auth
mkdir -p apps/web/src/features/onboarding
mkdir -p apps/web/pages/app

backup apps/web/src/lib/humanizeApiError.ts
backup apps/web/src/features/auth/ForgotPasswordPage.tsx
backup apps/web/src/features/auth/ResetPasswordPage.tsx
backup apps/web/src/features/onboarding/VerifyContactPage.tsx
backup apps/web/pages/forgot-password.tsx
backup apps/web/pages/reset-password.tsx
backup apps/web/pages/app/verify-contact.tsx

echo "==> Writing API helpers ..."
cat > apps/web/src/lib/api/verification.ts <<'EOF'
type JsonValue = any;

async function requestJson(
  endpoint: string,
  init: RequestInit
): Promise<JsonValue> {
  const res = await fetch(endpoint, {
    ...init,
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });

  const raw = await res.text();
  let data: JsonValue = null;

  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = raw;
  }

  if (!res.ok) {
    throw data ?? { message: `Request failed with status ${res.status}.` };
  }

  return data;
}

async function tryApi(init: RequestInit, path: string): Promise<JsonValue> {
  const endpoints = [`/backend-api${path}`, `/api${path}`];
  let lastError: unknown = null;

  for (const endpoint of endpoints) {
    try {
      return await requestJson(endpoint, init);
    } catch (error: any) {
      lastError = error;
      const message = typeof error === "string" ? error : error?.message ?? error?.error?.message;
      if (String(message ?? "").includes("404")) continue;
      if (error?.error?.code === "NOT_FOUND") continue;
      if (typeof error === "string" && error.includes("Request failed with status 404")) continue;
      if (error?.message === `Request failed with status 404.`) continue;
      throw error;
    }
  }

  throw lastError ?? new Error("Endpoint not found.");
}

export async function requestEmailVerification(email: string) {
  return tryApi(
    {
      method: "POST",
      body: JSON.stringify({ email }),
    },
    "/auth/verify-email/request"
  );
}

export async function confirmEmailVerification(email: string, code: string) {
  return tryApi(
    {
      method: "POST",
      body: JSON.stringify({ email, code }),
    },
    "/auth/verify-email/confirm"
  );
}

export async function requestPasswordReset(email: string) {
  return tryApi(
    {
      method: "POST",
      body: JSON.stringify({ email }),
    },
    "/auth/password/forgot"
  );
}

export async function resetPassword(token: string, password: string) {
  return tryApi(
    {
      method: "POST",
      body: JSON.stringify({ token, password }),
    },
    "/auth/password/reset"
  );
}

export async function fetchSession() {
  const endpoints = ["/backend-api/auth/session", "/api/auth/session"];
  let lastError: unknown = null;

  for (const endpoint of endpoints) {
    try {
      return await requestJson(endpoint, {
        method: "GET",
      });
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError ?? new Error("Unable to load session.");
}
EOF

echo "==> Enhancing human-friendly API error mapper ..."
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

    if (lower.includes("invalid or expired verification code")) {
      return "That verification code is invalid or has expired. Please request a new one.";
    }

    if (lower.includes("invalid or expired reset token")) {
      return "That password reset link is invalid or has expired. Please request a new one.";
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

  if (code === "VERIFY_EMAIL_CONFIRM_FAILED") {
    return "That verification code is invalid or has expired. Please request a new one.";
  }

  if (code === "PASSWORD_RESET_FAILED") {
    return "That password reset link is invalid or has expired. Please request a new one.";
  }

  if (code === "PASSWORD_TOO_SHORT") {
    return "Please choose a stronger password with at least 10 characters.";
  }

  if (typeof message === "string") {
    const lower = message.toLowerCase();

    if (lower.includes("invalid or expired verification code")) {
      return "That verification code is invalid or has expired. Please request a new one.";
    }

    if (lower.includes("too many verification attempts")) {
      return "Too many failed attempts. Please request a new verification code.";
    }

    if (lower.includes("invalid or expired reset token")) {
      return "That password reset link is invalid or has expired. Please request a new one.";
    }

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

echo "==> Writing ForgotPasswordPage ..."
cat > apps/web/src/features/auth/ForgotPasswordPage.tsx <<'EOF'
import Link from "next/link";
import { FormEvent, useState } from "react";
import { requestPasswordReset } from "../../lib/api/verification";
import { humanizeApiError } from "../../lib/humanizeApiError";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [successMessage, setSuccessMessage] = useState("");

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setErrorMessage("");
    setSuccessMessage("");

    try {
      const result = await requestPasswordReset(email.trim().toLowerCase());
      setSuccessMessage(
        result?.message ??
          "If an account exists for that email, a password reset email has been sent."
      );
    } catch (error) {
      setErrorMessage(humanizeApiError(error));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#020817] px-6 py-10 text-white">
      <div className="mx-auto max-w-3xl rounded-[36px] border border-white/10 bg-[#0b1730] p-10 shadow-2xl shadow-black/25">
        <h1 className="text-5xl font-semibold tracking-tight">Forgot password</h1>
        <p className="mt-4 text-2xl leading-relaxed text-slate-300">
          Enter your email address and we’ll send you a password reset email.
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
          <div>
            <label className="mb-3 block text-2xl font-semibold text-white">Email</label>
            <input
              type="email"
              value={email}
              autoComplete="email"
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-[22px] border border-white/10 bg-[#020817] px-6 py-5 text-2xl text-white outline-none transition placeholder:text-slate-500 focus:border-cyan-400"
              placeholder="you@example.com"
            />
          </div>

          <button
            type="submit"
            disabled={submitting}
            className="w-full rounded-[24px] border border-cyan-400/50 bg-cyan-500/20 px-6 py-5 text-3xl font-semibold text-cyan-100 transition hover:bg-cyan-500/30 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {submitting ? "Sending..." : "Send reset email"}
          </button>

          <p className="text-xl text-slate-300">
            <Link href="/login" className="font-semibold text-cyan-300 hover:text-cyan-200">
              Back to login
            </Link>
          </p>
        </form>
      </div>
    </div>
  );
}
EOF

echo "==> Writing ResetPasswordPage ..."
cat > apps/web/src/features/auth/ResetPasswordPage.tsx <<'EOF'
import Link from "next/link";
import { useRouter } from "next/router";
import { FormEvent, useMemo, useState } from "react";
import { resetPassword } from "../../lib/api/verification";
import { humanizeApiError } from "../../lib/humanizeApiError";

export default function ResetPasswordPage() {
  const router = useRouter();
  const token = useMemo(() => {
    const raw = router.query?.token;
    return typeof raw === "string" ? raw : "";
  }, [router.query]);

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [successMessage, setSuccessMessage] = useState("");

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setErrorMessage("");
    setSuccessMessage("");

    try {
      if (!token) {
        throw new Error("That password reset link is invalid or incomplete.");
      }

      if (password.length < 10) {
        throw new Error("Please choose a stronger password with at least 10 characters.");
      }

      if (password !== confirmPassword) {
        throw new Error("Your password confirmation does not match.");
      }

      const result = await resetPassword(token, password);
      setSuccessMessage(result?.message ?? "Password reset successfully.");
      setPassword("");
      setConfirmPassword("");
    } catch (error) {
      setErrorMessage(humanizeApiError(error));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#020817] px-6 py-10 text-white">
      <div className="mx-auto max-w-3xl rounded-[36px] border border-white/10 bg-[#0b1730] p-10 shadow-2xl shadow-black/25">
        <h1 className="text-5xl font-semibold tracking-tight">Reset password</h1>
        <p className="mt-4 text-2xl leading-relaxed text-slate-300">
          Enter your new password below.
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
          <div>
            <div className="mb-3 flex items-center justify-between">
              <label className="block text-2xl font-semibold text-white">New password</label>
              <button
                type="button"
                onClick={() => setShowPassword((prev) => !prev)}
                className="text-xl font-semibold text-cyan-300 hover:text-cyan-200"
              >
                {showPassword ? "Hide password" : "Show password"}
              </button>
            </div>
            <input
              type={showPassword ? "text" : "password"}
              value={password}
              autoComplete="new-password"
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-[22px] border border-white/10 bg-[#020817] px-6 py-5 text-2xl text-white outline-none transition placeholder:text-slate-500 focus:border-cyan-400"
            />
          </div>

          <div>
            <div className="mb-3 flex items-center justify-between">
              <label className="block text-2xl font-semibold text-white">Confirm password</label>
              <button
                type="button"
                onClick={() => setShowConfirmPassword((prev) => !prev)}
                className="text-xl font-semibold text-cyan-300 hover:text-cyan-200"
              >
                {showConfirmPassword ? "Hide password" : "Show password"}
              </button>
            </div>
            <input
              type={showConfirmPassword ? "text" : "password"}
              value={confirmPassword}
              autoComplete="new-password"
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="w-full rounded-[22px] border border-white/10 bg-[#020817] px-6 py-5 text-2xl text-white outline-none transition placeholder:text-slate-500 focus:border-cyan-400"
            />
          </div>

          <button
            type="submit"
            disabled={submitting}
            className="w-full rounded-[24px] border border-cyan-400/50 bg-cyan-500/20 px-6 py-5 text-3xl font-semibold text-cyan-100 transition hover:bg-cyan-500/30 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {submitting ? "Resetting..." : "Reset password"}
          </button>

          <p className="text-xl text-slate-300">
            <Link href="/login" className="font-semibold text-cyan-300 hover:text-cyan-200">
              Back to login
            </Link>
          </p>
        </form>
      </div>
    </div>
  );
}
EOF

echo "==> Writing VerifyContactPage ..."
cat > apps/web/src/features/onboarding/VerifyContactPage.tsx <<'EOF'
import Link from "next/link";
import { FormEvent, useEffect, useState } from "react";
import {
  confirmEmailVerification,
  fetchSession,
  requestEmailVerification,
} from "../../lib/api/verification";
import { humanizeApiError } from "../../lib/humanizeApiError";

export default function VerifyContactPage() {
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [loadingSession, setLoadingSession] = useState(true);
  const [sending, setSending] = useState(false);
  const [verifying, setVerifying] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [successMessage, setSuccessMessage] = useState("");

  useEffect(() => {
    let active = true;

    async function loadSession() {
      try {
        const data = await fetchSession();
        const sessionEmail =
          data?.user?.email ??
          data?.email ??
          data?.session?.user?.email ??
          "";
        if (active && sessionEmail) {
          setEmail(String(sessionEmail));
        }
      } catch {
        // Leave email editable if session fetch is unavailable.
      } finally {
        if (active) setLoadingSession(false);
      }
    }

    loadSession();
    return () => {
      active = false;
    };
  }, []);

  async function onSendCode(e: FormEvent) {
    e.preventDefault();
    setSending(true);
    setErrorMessage("");
    setSuccessMessage("");

    try {
      const result = await requestEmailVerification(email.trim().toLowerCase());
      setSuccessMessage(
        result?.message ??
          "If an account exists, a verification email has been sent."
      );
    } catch (error) {
      setErrorMessage(humanizeApiError(error));
    } finally {
      setSending(false);
    }
  }

  async function onVerifyCode(e: FormEvent) {
    e.preventDefault();
    setVerifying(true);
    setErrorMessage("");
    setSuccessMessage("");

    try {
      const result = await confirmEmailVerification(
        email.trim().toLowerCase(),
        code.trim()
      );
      setSuccessMessage(result?.message ?? "Email verified successfully.");
      setCode("");
    } catch (error) {
      setErrorMessage(humanizeApiError(error));
    } finally {
      setVerifying(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#020817] text-white">
      <div className="mx-auto max-w-[1500px] px-6 py-8">
        <div className="flex items-center justify-between border-b border-white/10 pb-6">
          <Link href="/" className="text-4xl font-semibold tracking-tight">
            DCapX
          </Link>
          <div className="flex items-center gap-8 text-xl text-slate-300">
            <Link href="/app/onboarding" className="hover:text-white">Onboarding</Link>
            <Link href="/app/consents" className="hover:text-white">Consents</Link>
            <Link href="/app/kyc" className="hover:text-white">KYC</Link>
          </div>
        </div>

        <div className="mx-auto mt-10 max-w-5xl">
          <h1 className="text-6xl font-semibold tracking-tight">Verify contact</h1>
          <p className="mt-4 max-w-4xl text-2xl leading-relaxed text-slate-300">
            Verify your email address to unlock the next onboarding steps.
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

          <div className="mt-8 grid gap-8 lg:grid-cols-2">
            <form
              onSubmit={onSendCode}
              className="rounded-[32px] border border-white/10 bg-[#0b1730] p-8 shadow-2xl shadow-black/25"
            >
              <h2 className="text-4xl font-semibold">Send verification email</h2>
              <p className="mt-3 text-xl leading-relaxed text-slate-300">
                We’ll send a one-time verification code to your email.
              </p>

              <div className="mt-8">
                <label className="mb-3 block text-2xl font-semibold text-white">Email</label>
                <input
                  type="email"
                  value={email}
                  autoComplete="email"
                  disabled={loadingSession}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full rounded-[22px] border border-white/10 bg-[#020817] px-6 py-5 text-2xl text-white outline-none transition placeholder:text-slate-500 focus:border-cyan-400 disabled:opacity-70"
                  placeholder="you@example.com"
                />
              </div>

              <button
                type="submit"
                disabled={sending || !email.trim()}
                className="mt-8 w-full rounded-[24px] border border-cyan-400/50 bg-cyan-500/20 px-6 py-5 text-3xl font-semibold text-cyan-100 transition hover:bg-cyan-500/30 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {sending ? "Sending..." : "Send code"}
              </button>
            </form>

            <form
              onSubmit={onVerifyCode}
              className="rounded-[32px] border border-white/10 bg-[#0b1730] p-8 shadow-2xl shadow-black/25"
            >
              <h2 className="text-4xl font-semibold">Enter verification code</h2>
              <p className="mt-3 text-xl leading-relaxed text-slate-300">
                Enter the code from your email to complete contact verification.
              </p>

              <div className="mt-8">
                <label className="mb-3 block text-2xl font-semibold text-white">Verification code</label>
                <input
                  type="text"
                  value={code}
                  inputMode="numeric"
                  onChange={(e) => setCode(e.target.value)}
                  className="w-full rounded-[22px] border border-white/10 bg-[#020817] px-6 py-5 text-2xl text-white outline-none transition placeholder:text-slate-500 focus:border-cyan-400"
                  placeholder="Enter code"
                />
              </div>

              <div className="mt-8 flex flex-wrap gap-4">
                <button
                  type="submit"
                  disabled={verifying || !email.trim() || !code.trim()}
                  className="rounded-[22px] border border-cyan-400/50 bg-cyan-500/20 px-8 py-4 text-2xl font-semibold text-cyan-100 transition hover:bg-cyan-500/30 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {verifying ? "Verifying..." : "Verify code"}
                </button>

                <Link
                  href="/app/onboarding"
                  className="rounded-[22px] border border-white/10 bg-white/[0.03] px-8 py-4 text-2xl font-semibold text-slate-200 transition hover:bg-white/[0.06]"
                >
                  Back to onboarding
                </Link>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}
EOF

echo "==> Writing route pages ..."
cat > apps/web/pages/forgot-password.tsx <<'EOF'
import ForgotPasswordPage from "../src/features/auth/ForgotPasswordPage";

export default ForgotPasswordPage;
EOF

cat > apps/web/pages/reset-password.tsx <<'EOF'
import ResetPasswordPage from "../src/features/auth/ResetPasswordPage";

export default ResetPasswordPage;
EOF

cat > apps/web/pages/app/verify-contact.tsx <<'EOF'
import VerifyContactPage from "../../src/features/onboarding/VerifyContactPage";

export default VerifyContactPage;
EOF

echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Frontend email verification + reset wiring pack applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
echo
echo "New / updated screens:"
echo "  /app/verify-contact"
echo "  /forgot-password"
echo "  /reset-password"
