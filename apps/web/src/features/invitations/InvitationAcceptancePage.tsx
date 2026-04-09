import React, { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/router";
import type { GetInvitationByTokenResponse } from "@dcapx/contracts";
import { acceptInvitation, getInvitationByToken } from "../../lib/api/invitations";
import PortalShell from "../ui/PortalShell";

function messageBox(kind: "error" | "success" | "info", message: string) {
  const classes =
    kind === "error"
      ? "border-rose-300 bg-rose-50 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200"
      : kind === "success"
      ? "border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200"
      : "border-cyan-300 bg-cyan-50 text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200";

  return (
    <div className={`rounded-2xl border px-4 py-3 text-sm ${classes}`}>
      {message}
    </div>
  );
}

function formatUtc(utc: string | null | undefined) {
  if (!utc) return "—";

  const date = new Date(utc);
  if (Number.isNaN(date.getTime())) return utc;

  return new Intl.DateTimeFormat("en-AU", {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(date);
}

export default function InvitationAcceptancePage() {
  const router = useRouter();
  const token = typeof router.query.token === "string" ? router.query.token : "";

  const [data, setData] = useState<GetInvitationByTokenResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isAccepting, setIsAccepting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!router.isReady || !token) return;

    let isMounted = true;

    async function load() {
      try {
        setIsLoading(true);
        setErrorMessage(null);

        const result = await getInvitationByToken(token);
        if (isMounted) setData(result);
      } catch (error: any) {
        if (isMounted) {
          setErrorMessage(
            error?.error?.message ||
              error?.message ||
              "Failed to load invitation."
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
  }, [router.isReady, token]);

  async function handleAccept() {
    try {
      setIsAccepting(true);
      setErrorMessage(null);
      setSuccessMessage(null);

      await acceptInvitation(token, { accept: true });

      setSuccessMessage("Invitation accepted successfully.");

      setTimeout(() => {
        router.push("/app/onboarding");
      }, 900);
    } catch (error: any) {
      setErrorMessage(
        error?.error?.message ||
          error?.message ||
          "Failed to accept invitation."
      );
    } finally {
      setIsAccepting(false);
    }
  }

  return (
    <PortalShell
      title="Invitation"
      description="Review the invitation details and accept the invitation to continue into the DCapX portal."
    >
      <div className="grid gap-6">
        {isLoading ? (
          <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <p className="text-sm text-slate-600 dark:text-slate-400">
              Loading invitation...
            </p>
          </div>
        ) : null}

        {!isLoading && errorMessage ? messageBox("error", errorMessage) : null}
        {!isLoading && successMessage ? messageBox("success", successMessage) : null}

        {!isLoading && data ? (
          <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <div className="grid gap-4 md:grid-cols-2">
              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
                <div className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                  Email
                </div>
                <div className="mt-2 text-sm font-medium">{data.email}</div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
                <div className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                  Invitation Type
                </div>
                <div className="mt-2 text-sm font-medium">{data.invitationType}</div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
                <div className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                  Target Role
                </div>
                <div className="mt-2 text-sm font-medium">{data.targetRoleCode}</div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
                <div className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                  Expires At
                </div>
                <div className="mt-2 text-sm font-medium">{formatUtc(data.expiresAtUtc)}</div>
              </div>
            </div>

            <div className="mt-6 flex flex-wrap gap-3">
              <button
                type="button"
                onClick={handleAccept}
                disabled={isAccepting || data.status !== "PENDING"}
                className="rounded-2xl border border-cyan-400/40 bg-cyan-400/10 px-5 py-3 text-sm font-medium text-cyan-700 transition hover:bg-cyan-400/20 disabled:cursor-not-allowed disabled:opacity-50 dark:text-cyan-200"
              >
                {isAccepting ? "Accepting..." : "Accept Invitation"}
              </button>

              <Link
                href="/login"
                className="rounded-2xl border border-slate-300 bg-white px-5 py-3 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
              >
                Go to Login
              </Link>
            </div>

            {data.status !== "PENDING" ? (
              <div className="mt-5">
                {messageBox("info", `This invitation is currently ${data.status}.`)}
              </div>
            ) : null}
          </section>
        ) : null}
      </div>
    </PortalShell>
  );
}
