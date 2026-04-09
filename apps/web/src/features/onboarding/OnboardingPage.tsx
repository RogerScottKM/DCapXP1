import React, { useEffect, useState } from "react";
import Link from "next/link";
import type { OnboardingStatusResponse } from "@dcapx/contracts";
import { getMyOnboardingStatus } from "../../lib/api/onboarding";
import { friendlyPortalError } from "../../lib/api/friendlyError";
import OnboardingProgress from "./OnboardingProgress";
import ReferralCard from "./ReferralCard";
import PortalShell from "../ui/PortalShell";

export default function OnboardingPage() {
  const [data, setData] = useState<OnboardingStatusResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;

    async function load() {
      try {
        setIsLoading(true);
        setErrorMessage(null);

        const result = await getMyOnboardingStatus();
        if (isMounted) setData(result);
      } catch (error: any) {
        if (isMounted) {
          setErrorMessage(
            friendlyPortalError(error, "Failed to load onboarding status.")
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
  }, []);

  const isAuthError = errorMessage === "Please sign in to continue.";

  return (
    <PortalShell
      title="Client Onboarding"
      description="Track your onboarding progress, complete the next required action, and move through identity, consent, and Aptivio readiness workflow steps."
    >
      <div className="grid gap-6">
        {isLoading ? (
          <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <p className="text-sm text-slate-600 dark:text-slate-400">
              Loading onboarding status...
            </p>
          </div>
        ) : null}

        {!isLoading && errorMessage ? (
          <div className="rounded-3xl border border-rose-300 bg-rose-50 p-6 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200">
            <strong>Error:</strong> {errorMessage}
          </div>
        ) : null}

        {!isLoading && isAuthError ? (
          <div className="rounded-3xl border border-cyan-300 bg-cyan-50 p-6 text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
            Please sign in first to view your onboarding progress.{" "}
            <Link href="/login" className="font-medium underline">
              Go to login
            </Link>
          </div>
        ) : null}

        {!isLoading && !isAuthError && !errorMessage && data ? (
          <>
            <OnboardingProgress data={data} />
            <ReferralCard referral={data.entities.referral} />
          </>
        ) : null}
      </div>
    </PortalShell>
  );
}
