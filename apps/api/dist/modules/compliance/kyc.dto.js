"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.upsertLegacyKycDto = exports.kycCaseQueueQueryDto = exports.adminKycCaseDecisionDto = exports.submitKycCaseDto = exports.uploadKycDocumentDto = exports.createKycCaseDto = exports.kycCaseIdParamDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
const enums_1 = require("../../lib/dto/enums");
// -------------------------
// New KycCase workflow DTOs
// -------------------------
exports.kycCaseIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.createKycCaseDto = zod_1.z.object({
    notes: zod_1.z.string().trim().max(1000).optional(),
});
exports.uploadKycDocumentDto = zod_1.z.object({
    docType: zod_1.z.enum(enums_1.kycDocumentTypeValues),
    fileKey: zod_1.z.string().trim().min(1).max(500),
    fileName: zod_1.z.string().trim().max(255).optional(),
    mimeType: zod_1.z.string().trim().max(100).optional(),
    metadata: common_1.jsonObjectSchema.optional(),
});
exports.submitKycCaseDto = zod_1.z.object({
    attestTruthfulness: zod_1.z.literal(true),
});
exports.adminKycCaseDecisionDto = zod_1.z.object({
    decision: zod_1.z.enum(enums_1.kycDecisionCodeValues),
    reasonCode: zod_1.z.string().trim().max(100).optional(),
    notes: zod_1.z.string().trim().max(2000).optional(),
});
exports.kycCaseQueueQueryDto = common_1.paginationQuerySchema.extend({
    status: zod_1.z.enum(enums_1.kycCaseStatusValues).optional(),
    userId: zod_1.z.string().cuid().optional(),
});
// -------------------------
// Legacy summary Kyc DTO
// Keep this for backfill/compat routes only
// -------------------------
exports.upsertLegacyKycDto = zod_1.z.object({
    legalName: zod_1.z.string().trim().min(1).max(200),
    country: common_1.countryCodeSchema,
    dob: common_1.isoDateTimeSchema,
    docType: zod_1.z.string().trim().min(1).max(100),
    docHash: zod_1.z.string().trim().min(8).max(255),
    status: zod_1.z.enum(enums_1.kycStatusValues).default("PENDING"),
    riskScore: common_1.nonNegativeDecimalStringSchema.optional(),
});
