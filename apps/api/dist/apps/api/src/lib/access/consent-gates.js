"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.assertAdvisorCanViewClientAptivio = assertAdvisorCanViewClientAptivio;
const api_error_1 = require("../errors/api-error");
async function assertAdvisorCanViewClientAptivio(prisma, advisorUserId, clientId) { const assignment = await prisma.advisorClientAssignment.findFirst({ where: { advisorUserId, clientUserId: clientId, status: "ACTIVE" } }); if (!assignment) {
    throw new api_error_1.ApiError({ statusCode: 403, code: "ADVISOR_NOT_ASSIGNED", message: "Advisor is not assigned to this client." });
} const consent = await prisma.consentRecord.findFirst({ where: { userId: clientId, consentType: "ADVISOR_DATA_SHARING_CONSENT", revokedAt: null }, orderBy: { acceptedAt: "desc" } }); return { assignment, consent, canViewSummary: Boolean(consent) }; }
