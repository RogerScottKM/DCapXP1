import type { AdvisorAptivioSummaryResponse } from "@dcapx/contracts";
import { prisma } from "../../db";
import { ApiError } from "../../lib/errors/api-error";
import { toUtcIso } from "../../lib/time/utc";
import { assertAdvisorCanViewClientAptivio } from "../../lib/access/consent-gates";
import { ADVISOR_APTIVIO_DISCLAIMER } from "./advisor.aptivio.mapper";

class AdvisorService {
  async getClientAptivioSummary(
    advisorUserId: string,
    clientId: string
  ): Promise<AdvisorAptivioSummaryResponse> {
    const { consent, canViewSummary } = await assertAdvisorCanViewClientAptivio(
      prisma,
      advisorUserId,
      clientId
    );

    const client = await prisma.user.findUnique({
  where: { id: clientId },
  select: {
    id: true,
    username: true,
    profile: {
      select: {
        firstName: true,
        lastName: true,
      },
    },
  },
});

if (!client) {
  throw new ApiError({
    statusCode: 404,
    code: "CLIENT_NOT_FOUND",
    message: "Client not found.",
  });
}

const clientDisplayName =
  [client.profile?.firstName, client.profile?.lastName].filter(Boolean).join(" ") ||
  client.username;

    const aptivioProfile = await prisma.aptivioProfile.findUnique({
      where: { userId: clientId },
    });
    return {
      clientId,
      clientDisplayName:
        [client.profile?.firstName, client.profile?.lastName].filter(Boolean).join(" ") ||
        client.username,
      consent: {
        canViewSummary,
        consentType: "ADVISOR_DATA_SHARING_CONSENT",
        consentVersion: consent?.version ?? null,
        consentedAtUtc: toUtcIso(consent?.acceptedAt),
      },
      disclaimer: ADVISOR_APTIVIO_DISCLAIMER,
      summary:
        canViewSummary && aptivioProfile
          ? {
              assessmentCode: aptivioProfile.latestAssessmentCode ?? "APTIVIO_CORE",
              assessmentVersion: aptivioProfile.latestAssessmentVersion ?? 1,
              assessedAtUtc: toUtcIso(aptivioProfile.assessedAt) ?? new Date().toISOString(),
              confidenceLevel: (aptivioProfile.confidenceLevel as "LOW" | "MEDIUM" | "HIGH") ?? "MEDIUM",
              scores: {
                overallReadinessScore: aptivioProfile.overallReadinessScore ?? 0,
              },
              bands: {
                riskBand: aptivioProfile.riskBand as any,
                lossCapacityBand: aptivioProfile.lossCapacityBand as any,
                liquidityNeedBand: aptivioProfile.liquidityNeedBand as any,
                timeHorizonBand: aptivioProfile.timeHorizonBand as any,
                knowledgeExperienceBand: aptivioProfile.knowledgeExperienceBand as any,
                behaviouralStabilityBand: aptivioProfile.behaviouralStabilityBand as any,
              },
              suitability: {
                status: aptivioProfile.suitabilityStatus as any,
                rationaleCodes: (aptivioProfile.suitabilityRationaleCodes as string[]) ?? [],
              },
              eligibility: {
                aptivioIdStatus: aptivioProfile.aptivioIdEligibilityStatus as any,
                digitalTwinStatus: aptivioProfile.digitalTwinEligibilityStatus as any,
              },
              flags: (aptivioProfile.flagsJson as any[]) ?? [],
              prompts: (aptivioProfile.promptsJson as any[]) ?? [],
            }
          : null,
      visibility: {
        rawAnswersVisible: false,
        perQuestionResponsesVisible: false,
        scoringFormulaVisible: false,
      },
      metadata: {
        generatedAtUtc: new Date().toISOString(),
        source: "APTIVIO_PROFILE",
      },
    };
  }
}
export const advisorService = new AdvisorService();
