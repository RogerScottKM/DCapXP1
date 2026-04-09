import React, { useState } from "react";
import { useRouter } from "next/router";
import Link from "next/link";
import { friendlyPortalError } from "../../lib/api/friendlyError";
import { sendOtp, verifyOtp } from "../../lib/api/auth";
import PortalShell from "../ui/PortalShell";

export default function VerifyContactPage() {
  const router = useRouter();

  const [channel, setChannel] = useState<"EMAIL" | "SMS">("EMAIL");
  const [code, setCode] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [devOtpCode, setDevOtpCode] = useState<string | null>(null);
  const [destinationMasked, setDestinationMasked] = useState<string | null>(null);

  async function handleSendOtp() {
    try {
      setIsSending(true);
      setErrorMessage(null);
      setSuccessMessage(null);
      setDevOtpCode(null);

      const result = await sendOtp({ channel });

      setSuccessMessage(result.message);
      setDestinationMasked(result.destinationMasked);
      if (result.devOtpCode) {
        setDevOtpCode(result.devOtpCode);
      }
    } catch (error: any) {
      setErrorMessage(
        friendlyPortalError(error, "Failed to send verification code.")
      );
    } finally {
      setIsSending(false);
    }
  }

  async function handleVerify(e: React.FormEvent) {
    e.preventDefault();

    if (!code.trim()) {
      setErrorMessage("Please enter the verification code.");
      return;
    }

    try {
      setIsVerifying(true);
      setErrorMessage(null);
      setSuccessMessage(null);

      const result = await verifyOtp({
        channel,
        code: code.trim(),
      });

      setSuccessMessage(result.message);

      setTimeout(() => {
        router.push("/app/onboarding");
      }, 900);
    } catch (error: any) {
      setErrorMessage(
        friendlyPortalError(error, "Failed to verify code.")
      );
    } finally {
      setIsVerifying(false);
    }
  }

  return (
    <PortalShell
      title="Verify Contact"
      description="Verify your email or phone number to unlock the next onboarding steps."
    >
      <div className="grid gap-6">
        {errorMessage ? (
          <div className="rounded-2xl border border-rose-300 bg-rose-50 px-4 py-3 text-sm text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200">
            <strong>Error:</strong> {errorMessage}
          </div>
        ) : null}

        {successMessage ? (
          <div className="rounded-2xl border border-emerald-300 bg-emerald-50 px-4 py-3 text-sm text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200">
            <strong>Success:</strong> {successMessage}
          </div>
        ) : null}

        {devOtpCode ? (
          <div className="rounded-2xl border border-cyan-300 bg-cyan-50 px-4 py-3 text-sm text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
            <div className="font-medium">Development OTP code</div>
            <div className="mt-2 text-lg font-semibold tracking-widest">{devOtpCode}</div>
            {destinationMasked ? (
              <div className="mt-1 text-xs">Sent to {destinationMasked}</div>
            ) : null}
          </div>
        ) : null}

        <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
          <h2 className="text-xl font-semibold tracking-tight">Send verification code</h2>

          <div className="mt-5 max-w-sm">
            <label
              htmlFor="channel"
              className="block text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              Channel
            </label>
            <select
              id="channel"
              value={channel}
              onChange={(e) => setChannel(e.target.value as "EMAIL" | "SMS")}
              className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
            >
              <option value="EMAIL">Email</option>
              <option value="SMS">SMS</option>
            </select>
          </div>

          <button
            type="button"
            onClick={handleSendOtp}
            disabled={isSending}
            className="mt-5 rounded-2xl border border-cyan-300 bg-cyan-50 px-5 py-3 text-sm font-medium text-cyan-800 transition hover:bg-cyan-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-cyan-400/40 dark:bg-cyan-400/10 dark:text-cyan-100 dark:hover:bg-cyan-400/20"
          >
            {isSending ? "Sending..." : "Send code"}
          </button>
        </section>

        <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
          <h2 className="text-xl font-semibold tracking-tight">Enter verification code</h2>

          <form onSubmit={handleVerify} className="mt-5 max-w-sm space-y-5">
            <div>
              <label
                htmlFor="otpCode"
                className="block text-sm font-medium text-slate-700 dark:text-slate-200"
              >
                Verification code
              </label>
              <input
                id="otpCode"
                value={code}
                onChange={(e) => setCode(e.target.value)}
                placeholder="Enter 6-digit code"
                className="mt-2 w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-white"
              />
            </div>

            <div className="flex flex-wrap gap-3">
              <button
                type="submit"
                disabled={isVerifying}
                className="rounded-2xl border border-cyan-300 bg-cyan-50 px-5 py-3 text-sm font-medium text-cyan-800 transition hover:bg-cyan-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-cyan-400/40 dark:bg-cyan-400/10 dark:text-cyan-100 dark:hover:bg-cyan-400/20"
              >
                {isVerifying ? "Verifying..." : "Verify code"}
              </button>

              <Link
                href="/app/onboarding"
                className="rounded-2xl border border-slate-300 bg-white px-5 py-3 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
              >
                Back to onboarding
              </Link>
            </div>
          </form>
        </section>
      </div>
    </PortalShell>
  );
}
