import React from "react";
import type { OnboardingStatusResponse } from "@dcapx/contracts";

type Props = {
  data: OnboardingStatusResponse;
};

export default function OnboardingProgress({ data }: Props) {
  return (
    <section style={{ display: "grid", gap: 16 }}>
      <div style={{ border: "1px solid #ddd", borderRadius: 8, padding: 16 }}>
        <h2 style={{ marginTop: 0 }}>Onboarding Progress</h2>
        <p>
          <strong>Status:</strong> {data.overallStatus}
        </p>
        <p>
          <strong>Completion:</strong> {data.completionPercent}%
        </p>
        {data.nextRecommendedAction ? (
          <p>
            <strong>Next step:</strong> {data.nextRecommendedAction.label}
          </p>
        ) : (
          <p>
            <strong>Next step:</strong> None
          </p>
        )}
      </div>

      <div style={{ border: "1px solid #ddd", borderRadius: 8, padding: 16 }}>
        <h3 style={{ marginTop: 0 }}>Steps</h3>
        <ul style={{ paddingLeft: 20, marginBottom: 0 }}>
          {data.steps.map((step) => (
            <li key={step.code} style={{ marginBottom: 10 }}>
              <div>
                <strong>{step.label}</strong>
              </div>
              <div>Status: {step.status}</div>
              <div>Required: {step.required ? "Yes" : "No"}</div>
              {step.completedAtUtc ? <div>Completed: {step.completedAtUtc}</div> : null}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
