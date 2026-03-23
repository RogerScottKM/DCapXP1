import React, { useEffect, useState } from "react";
import type { OnboardingStatusResponse } from "@dcapx/contracts";
import { getMyOnboardingStatus } from "@/src/lib/api/onboarding";
import OnboardingProgress from "./OnboardingProgress";

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
        if (isMounted) {
          setData(result);
        }
      }catch (error: any) {
        if (isMounted) {
    setErrorMessage(
      error?.error?.message ||
      error?.message ||
      "Failed to load onboarding status."
      );
     } 
    } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    load();

    return () => {
      isMounted = false;
    };
  }, []);

  return (
    <main style={{ maxWidth: 900, margin: "0 auto", padding: 24 }}>
      <h1>Client Onboarding</h1>

      {isLoading ? <p>Loading onboarding status...</p> : null}

      {!isLoading && errorMessage ? (
        <div style={{ border: "1px solid #f0b4b4", borderRadius: 8, padding: 16 }}>
          <p style={{ margin: 0 }}>
            <strong>Error:</strong> {errorMessage}
          </p>
        </div>
      ) : null}

      {!isLoading && !errorMessage && data ? <OnboardingProgress data={data} /> : null}
    </main>
  );
}
