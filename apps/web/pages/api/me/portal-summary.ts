import type { NextApiRequest, NextApiResponse } from "next";

type UpstreamResult = {
  ok: boolean;
  status: number;
  data: any;
};

function getApiBase(): string {
  return process.env.API_INTERNAL_URL ?? "http://api:4010";
}

async function fetchUpstream(
  req: NextApiRequest,
  pathCandidates: string[]
): Promise<UpstreamResult> {
  const base = getApiBase().replace(/\/+$/, "");
  const cookie = req.headers.cookie ?? "";

  let last: UpstreamResult = {
    ok: false,
    status: 404,
    data: null,
  };

  for (const path of pathCandidates) {
    const url = `${base}${path}`;
    try {
      const response = await fetch(url, {
        method: "GET",
        headers: {
          Accept: "application/json",
          ...(cookie ? { cookie } : {}),
        },
      });

      const raw = await response.text();
      let data: any = null;
      try {
        data = raw ? JSON.parse(raw) : null;
      } catch {
        data = raw;
      }

      const result: UpstreamResult = {
        ok: response.ok,
        status: response.status,
        data,
      };

      if (response.ok || response.status === 401 || response.status === 403) {
        return result;
      }

      last = result;
    } catch (error: any) {
      last = {
        ok: false,
        status: 500,
        data: {
          error: {
            message: error?.message ?? "Upstream request failed.",
          },
        },
      };
    }
  }

  return last;
}

function pickUser(sessionData: any) {
  return (
    sessionData?.user ??
    sessionData?.session?.user ??
    sessionData?.data?.user ??
    null
  );
}

function pickDisplayName(user: any): string | null {
  if (!user) return null;
  if (user.displayName) return String(user.displayName);
  if (user.name) return String(user.name);

  const firstName = user.firstName ?? user.first_name ?? null;
  const lastName = user.lastName ?? user.last_name ?? null;

  if (firstName || lastName) {
    return [firstName, lastName].filter(Boolean).join(" ");
  }

  return user.username ?? user.email ?? null;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const session = await fetchUpstream(req, [
    "/api/auth/session",
    "/backend-api/auth/session",
    "/auth/session",
  ]);

  if (session.status === 401 || session.status === 403 || !session.ok) {
    return res.status(401).json({
      error: {
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      },
    });
  }

  const user = pickUser(session.data);

  const onboarding = await fetchUpstream(req, [
    "/api/me/onboarding-status",
    "/backend-api/me/onboarding-status",
    "/me/onboarding-status",
  ]);

  const kyc = await fetchUpstream(req, [
    "/api/me/kyc-case",
    "/backend-api/me/kyc-case",
    "/me/kyc-case",
  ]);

  const referral = await fetchUpstream(req, [
    "/api/me/referral-status",
    "/backend-api/me/referral-status",
    "/me/referral-status",
  ]);

  const onboardingData = onboarding.ok ? onboarding.data : null;
  const kycData = kyc.ok ? kyc.data : null;
  const referralData = referral.ok ? referral.data : null;

  const kycStatus =
    kycData?.status ??
    onboardingData?.entities?.kycCase?.status ??
    null;

  const payload = {
    displayName: pickDisplayName(user),
    username: user?.username ?? null,
    email: user?.email ?? null,
    userStatus: user?.status ?? onboardingData?.overallStatus ?? null,
    onboarding: {
      overallStatus: onboardingData?.overallStatus ?? null,
      completionPercent: Number(onboardingData?.completionPercent ?? 0),
      nextStepLabel:
        onboardingData?.nextRecommendedAction?.label ??
        onboardingData?.currentStep ??
        null,
    },
    verification: {
      emailVerified: Boolean(user?.emailVerifiedAt),
      phoneVerified: Boolean(user?.phoneVerifiedAt),
    },
    kyc: {
      status: kycStatus,
    },
    referral: {
      appliedCode:
        referralData?.appliedCode ??
        onboardingData?.entities?.referral?.appliedCode ??
        null,
      attributionStatus:
        referralData?.attributionStatus ??
        onboardingData?.entities?.referral?.attributionStatus ??
        null,
      pointsBalance:
        typeof referralData?.pointsBalance === "number"
          ? referralData.pointsBalance
          : typeof onboardingData?.entities?.referral?.pointsBalance === "number"
            ? onboardingData.entities.referral.pointsBalance
            : null,
    },
    portfolio: {
      totalAssetValue: null,
    },
  };

  return res.status(200).json(payload);
}
