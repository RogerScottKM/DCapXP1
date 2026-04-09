export type PortalSummary = {
  displayName: string | null;
  username: string | null;
  email: string | null;
  userStatus: string | null;
  onboarding: {
    overallStatus: string | null;
    completionPercent: number;
    nextStepLabel: string | null;
  };
  verification: {
    emailVerified: boolean;
    phoneVerified: boolean;
  };
  kyc: {
    status: string | null;
  };
  referral: {
    appliedCode: string | null;
    attributionStatus: string | null;
    pointsBalance: number | null;
  };
  portfolio: {
    totalAssetValue: string | null;
  };
};

export async function fetchPortalSummary(): Promise<PortalSummary> {
  const res = await fetch("/api/me/portal-summary", {
    credentials: "include",
    headers: {
      Accept: "application/json",
    },
  });

  const raw = await res.text();
  let data: any = null;

  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = raw;
  }

  if (!res.ok) {
    throw data ?? { message: `Request failed with status ${res.status}.` };
  }

  return data as PortalSummary;
}
