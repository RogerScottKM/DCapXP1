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
