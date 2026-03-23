import React, { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/router";
import type {
  AcceptConsentsRequest,
  ConsentType,
  GetRequiredConsentsResponse,
} from "@dcapx/contracts";
import { acceptConsents, getRequiredConsents } from "../../lib/api/consents";

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
          error?.error?.message ||
            error?.message ||
            "Failed to load required consents."
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
        error?.error?.message ||
          error?.message ||
          "Failed to accept consents."
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main style={{ maxWidth: 900, margin: "0 auto", padding: 24 }}>
      <h1>Required Consents</h1>
      <p>
        Please review and accept the required consents before continuing with
        onboarding.
      </p>

      {isLoading ? <p>Loading required consents...</p> : null}

      {!isLoading && errorMessage ? (
        <div
          style={{
            border: "1px solid #f0b4b4",
            borderRadius: 8,
            padding: 16,
            marginBottom: 16,
          }}
        >
          <p style={{ margin: 0 }}>
            <strong>Error:</strong> {errorMessage}
          </p>
        </div>
      ) : null}

      {!isLoading && successMessage ? (
        <div
          style={{
            border: "1px solid #b7e3c0",
            borderRadius: 8,
            padding: 16,
            marginBottom: 16,
          }}
        >
          <p style={{ margin: 0 }}>
            <strong>Success:</strong> {successMessage}
          </p>
        </div>
      ) : null}

      {!isLoading && data ? (
        <form onSubmit={handleSubmit} style={{ display: "grid", gap: 16 }}>
          <div
            style={{
              border: "1px solid #ddd",
              borderRadius: 8,
              padding: 16,
              display: "grid",
              gap: 14,
            }}
          >
            {data.items.map((item) => (
              <label
                key={`${item.consentType}:${item.version}`}
                style={{
                  display: "flex",
                  alignItems: "flex-start",
                  gap: 10,
                  cursor: "pointer",
                }}
              >
                <input
                  type="checkbox"
                  checked={Boolean(selected[item.consentType])}
                  onChange={() => toggleConsent(item.consentType)}
                  disabled={isSubmitting}
                  style={{ marginTop: 3 }}
                />
                <span>
                  <strong>{item.label}</strong>{" "}
                  {item.required ? "(Required)" : "(Optional)"} — version{" "}
                  {item.version}
                </span>
              </label>
            ))}
          </div>

          <div style={{ display: "flex", gap: 12 }}>
            <button
              type="submit"
              disabled={!allRequiredChecked || isSubmitting}
              style={{
                padding: "10px 16px",
                borderRadius: 8,
                border: "1px solid #222",
                cursor: !allRequiredChecked || isSubmitting ? "not-allowed" : "pointer",
              }}
            >
              {isSubmitting ? "Submitting..." : "Accept and Continue"}
            </button>

            <button
              type="button"
              onClick={() => router.push("/app/onboarding")}
              disabled={isSubmitting}
              style={{
                padding: "10px 16px",
                borderRadius: 8,
                border: "1px solid #999",
                cursor: isSubmitting ? "not-allowed" : "pointer",
              }}
            >
              Back to Onboarding
            </button>
          </div>
        </form>
      ) : null}
    </main>
  );
}
