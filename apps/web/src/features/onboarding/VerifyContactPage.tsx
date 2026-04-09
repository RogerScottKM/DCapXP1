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
