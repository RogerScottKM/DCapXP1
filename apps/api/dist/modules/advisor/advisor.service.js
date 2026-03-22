"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.advisorService = void 0;
const db_1 = require("../../db");
const api_error_1 = require("../../lib/errors/api-error");
const utc_1 = require("../../lib/time/utc");
const consent_gates_1 = require("../../lib/access/consent-gates");
const advisor_aptivio_mapper_1 = require("./advisor.aptivio.mapper");
class AdvisorService {
    async getClientAptivioSummary(advisorUserId, clientId) {
        const { consent, canViewSummary } = await (0, consent_gates_1.assertAdvisorCanViewClientAptivio)(db_1.prisma, advisorUserId, clientId);
        const client = await db_1.prisma.user.findUnique({
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
            throw new api_error_1.ApiError({
                statusCode: 404,
                code: "CLIENT_NOT_FOUND",
                message: "Client not found.",
            });
        }
        const clientDisplayName = [client.profile?.firstName, client.profile?.lastName].filter(Boolean).join(" ") ||
            client.username;
        const aptivioProfile = await db_1.prisma.aptivioProfile.findUnique({
            where: { userId: clientId },
        });
        return {
            clientId,
            clientDisplayName: [client.firstName, client.lastName].filter(Boolean).join(" "),
            consent: {
                canViewSummary,
                consentType: "ADVISOR_DATA_SHARING_CONSENT",
                consentVersion: consent?.version ?? null,
                consentedAtUtc: (0, utc_1.toUtcIso)(consent?.acceptedAt),
            },
            disclaimer: advisor_aptivio_mapper_1.ADVISOR_APTIVIO_DISCLAIMER,
            summary: canViewSummary && aptivioProfile
                ? {
                    assessmentCode: aptivioProfile.latestAssessmentCode ?? "APTIVIO_CORE",
                    assessmentVersion: aptivioProfile.latestAssessmentVersion ?? 1,
                    assessedAtUtc: (0, utc_1.toUtcIso)(aptivioProfile.assessedAt) ?? new Date().toISOString(),
                    confidenceLevel: aptivioProfile.confidenceLevel ?? "MEDIUM",
                    scores: {
                        overallReadinessScore: aptivioProfile.overallReadinessScore ?? 0,
                    },
                    bands: {
                        riskBand: aptivioProfile.riskBand,
                        lossCapacityBand: aptivioProfile.lossCapacityBand,
                        liquidityNeedBand: aptivioProfile.liquidityNeedBand,
                        timeHorizonBand: aptivioProfile.timeHorizonBand,
                        knowledgeExperienceBand: aptivioProfile.knowledgeExperienceBand,
                        behaviouralStabilityBand: aptivioProfile.behaviouralStabilityBand,
                    },
                    suitability: {
                        status: aptivioProfile.suitabilityStatus,
                        rationaleCodes: aptivioProfile.suitabilityRationaleCodes ?? [],
                    },
                    eligibility: {
                        aptivioIdStatus: aptivioProfile.aptivioIdEligibilityStatus,
                        digitalTwinStatus: aptivioProfile.digitalTwinEligibilityStatus,
                    },
                    flags: aptivioProfile.flagsJson ?? [],
                    prompts: aptivioProfile.promptsJson ?? [],
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
exports.advisorService = new AdvisorService();
