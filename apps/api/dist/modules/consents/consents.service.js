"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.consentsService = void 0;
const db_1 = require("../../db");
const REQUIRED_CONSENTS = [
    { consentType: "TERMS_OF_SERVICE", version: "v1", label: "Terms of Service", required: true },
    { consentType: "PRIVACY_POLICY", version: "v1", label: "Privacy Policy", required: true },
    { consentType: "DATA_PROCESSING", version: "v1", label: "Data Processing", required: true },
    { consentType: "ELECTRONIC_COMMUNICATION", version: "v1", label: "Electronic Communication", required: true },
    { consentType: "APTIVIO_ASSESSMENT_AUTH", version: "v1", label: "Aptivio Assessment Authorisation", required: true },
];
class ConsentsService {
    async getRequiredConsents(userId) {
        const existing = await db_1.prisma.consentRecord.findMany({ where: { userId, revokedAt: null } });
        const accepted = new Set(existing.map((x) => x.consentType));
        return {
            items: [...REQUIRED_CONSENTS],
            missingConsentTypes: REQUIRED_CONSENTS
                .filter((x) => !accepted.has(x.consentType))
                .map((x) => x.consentType),
        };
    }
    async acceptConsents(userId, request) {
        await db_1.prisma.$transaction(request.items.map((item) => db_1.prisma.consentRecord.create({
            data: { userId, consentType: item.consentType, version: item.version },
        })));
        const saved = await db_1.prisma.consentRecord.findMany({
            where: { userId, revokedAt: null },
            orderBy: { acceptedAt: "desc" },
        });
        return saved.map((x) => ({
            consentType: x.consentType,
            version: x.version,
            acceptedAtUtc: x.acceptedAt.toISOString(),
            revokedAtUtc: x.revokedAt?.toISOString() ?? null,
        }));
    }
}
exports.consentsService = new ConsentsService();
