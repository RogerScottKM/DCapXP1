import React, { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/router";
import type {
  AcceptConsentsRequest,
  ConsentType,
  GetRequiredConsentsResponse,
} from "@dcapx/contracts";
import { acceptConsents, getRequiredConsents } from "../../lib/api/consents";
import { friendlyPortalError } from "../../lib/api/friendlyError";
import PortalShell from "../ui/PortalShell";

function statusMessageBox(kind: "error" | "success", message: string) {
  const base = "rounded-2xl border px-4 py-3 text-sm";
  const classes =
    kind === "error"
      ? "border-rose-300 bg-rose-50 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200"
      : "border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200";

  return (
    <div className={`${base} ${classes}`}>
      <span className="font-medium">
        {kind === "error" ? "Error:" : "Success:"}
      </span>{" "}
      {message}
    </div>
  );
}

export default function ConsentsPage() {
  const router = useRouter();

  const [data, setData] = useState<GetRequiredConsentsResponse | null>(null);
  const [selected, setSelected] = useState<Record<string, boolean>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;

    async function load() {
      try {
        setIsLoading(true);
        setErrorMessage(null);

        const result = await getRequiredConsents();

        if (!isMounted) return;

        setData(result);

        const nextSelected: Record<string, boolean> = {};
        for (const item of result.items) {
          nextSelected[item.consentType] = false;
        }
        setSelected(nextSelected);
      } catch (error: any) {
        if (!isMounted) return;
        setErrorMessage(
          friendlyPortalError(error, "Failed to load required consents.")
        );
      } finally {
        if (isMounted) setIsLoading(false);
      }
    }

    load();

    return () => {
      isMounted = false;
    };
  }, []);

  const requiredItems = useMemo(() => {
    return data?.items.filter((item) => item.required) ?? [];
  }, [data]);

  const allRequiredChecked = useMemo(() => {
    if (!requiredItems.length) return false;
    return requiredItems.every((item) => Boolean(selected[item.consentType]));
  }, [requiredItems, selected]);

  const isAuthError = errorMessage === "Please sign in to continue.";

  function toggleConsent(consentType: ConsentType) {
    setSelected((prev) => ({
      ...prev,
      [consentType]: !prev[consentType],
    }));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    if (!data) return;

    const itemsToAccept: AcceptConsentsRequest["items"] = data.items
      .filter((item) => selected[item.consentType])
      .map((item) => ({
        consentType: item.consentType,
        version: item.version,
      }));

    if (itemsToAccept.length === 0) {
      setErrorMessage("Please accept the required consents before continuing.");
      return;
    }

    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      setSuccessMessage(null);

      await acceptConsents({ items: itemsToAccept });

      setSuccessMessage("Consents accepted successfully.");

      setTimeout(() => {
        router.push("/app/onboarding");
      }, 800);
    } catch (error: any) {
      setErrorMessage(
        friendlyPortalError(error, "Failed to accept consents.")
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <PortalShell
      title="Required Consents"
      description="Review and accept the required legal, data-processing, and Aptivio-related consents before continuing through onboarding."
    >
      <div className="grid gap-6">
        {isLoading ? (
          <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <p className="text-sm text-slate-600 dark:text-slate-400">
              Loading required consents...
            </p>
          </div>
        ) : null}

        {!isLoading && errorMessage ? statusMessageBox("error", errorMessage) : null}
        {!isLoading && successMessage ? statusMessageBox("success", successMessage) : null}

        {isAuthError ? (
          <div className="rounded-2xl border border-cyan-300 bg-cyan-50 px-4 py-3 text-sm text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
            Please sign in first to review and accept consents.{" "}
            <Link href="/login" className="font-medium underline">
              Go to login
            </Link>
          </div>
        ) : null}

        {!isLoading && data && !isAuthError ? (
          <form onSubmit={handleSubmit} className="grid gap-6">
            <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
              <div className="mb-6 flex items-start justify-between gap-4">
                <div>
                  <h2 className="text-xl font-semibold tracking-tight">
                    Consent Checklist
                  </h2>
                  <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">
                    All required items must be accepted before you can continue.
                  </p>
                </div>

                <span className="rounded-full border border-cyan-300 bg-cyan-50 px-3 py-1 text-xs font-medium text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
                  {data.missingConsentTypes.length} missing
                </span>
              </div>

              <div className="grid gap-4">
                {data.items.map((item) => {
                  const isChecked = Boolean(selected[item.consentType]);

                  return (
                    <label
                      key={`${item.consentType}:${item.version}`}
                      className="flex cursor-pointer items-start gap-4 rounded-2xl border border-slate-200 bg-slate-50 p-4 transition hover:bg-slate-100 dark:border-slate-800 dark:bg-slate-950/60 dark:hover:bg-slate-900"
                    >
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={() => toggleConsent(item.consentType)}
                        disabled={isSubmitting}
                        className="mt-1 h-4 w-4 rounded border-slate-300 text-cyan-600 focus:ring-cyan-500 dark:border-slate-700 dark:bg-slate-900"
                      />

                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="text-sm font-medium text-slate-900 dark:text-slate-100">
                            {item.label}
                          </span>

                          <span
                            className={`rounded-full px-2.5 py-1 text-[11px] font-medium ${
                              item.required
                                ? "border border-amber-300 bg-amber-50 text-amber-700 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200"
                                : "border border-slate-300 bg-slate-100 text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300"
                            }`}
                          >
                            {item.required ? "Required" : "Optional"}
                          </span>

                          <span className="text-xs text-slate-500 dark:text-slate-400">
                            Version {item.version}
                          </span>
                        </div>
                      </div>
                    </label>
                  );
                })}
              </div>
            </div>

            <div className="flex flex-wrap gap-3">
              <button
                type="submit"
                disabled={!allRequiredChecked || isSubmitting}
                className="rounded-2xl border border-cyan-400/40 bg-cyan-400/10 px-5 py-3 text-sm font-medium text-cyan-700 transition hover:bg-cyan-400/20 disabled:cursor-not-allowed disabled:opacity-50 dark:text-cyan-200"
              >
                {isSubmitting ? "Submitting..." : "Accept and Continue"}
              </button>

              <button
                type="button"
                onClick={() => router.push("/app/onboarding")}
                disabled={isSubmitting}
                className="rounded-2xl border border-slate-300 bg-white px-5 py-3 text-sm font-medium text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
              >
                Back to Onboarding
              </button>
            </div>
          </form>
        ) : null}
      </div>
    </PortalShell>
  );
}
