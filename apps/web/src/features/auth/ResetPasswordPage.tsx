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
