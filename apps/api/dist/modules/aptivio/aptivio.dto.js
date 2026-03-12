"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateDigitalTwinPreferencesDto = exports.issueAptivioIdentityDto = exports.completeAssessmentDto = exports.startAssessmentDto = exports.updateAptivioProfileStatusDto = exports.aptivioProfileInitDto = exports.assessmentRunIdParamDto = exports.aptivioProfileIdParamDto = exports.skillPassportCertificationDto = exports.skillPassportSkillDto = exports.aptitudeScoreDto = exports.aptitudeSourceDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
const enums_1 = require("../../lib/dto/enums");
exports.aptitudeSourceDto = zod_1.z.object({
    type: zod_1.z.enum([
        "simulation",
        "assessment",
        "manager_review",
        "peer_review",
        "work_artefact",
        "other",
    ]),
    refId: zod_1.z.string().trim().max(100).optional(),
    weight: zod_1.z.number().min(0).max(1).optional(),
});
exports.aptitudeScoreDto = zod_1.z.object({
    id: zod_1.z.string().trim().min(1).max(100),
    name: zod_1.z.string().trim().min(1).max(200),
    score: zod_1.z.number().int().min(0).max(100),
    confidence: zod_1.z.number().min(0).max(1).optional(),
    weightForRole: zod_1.z.number().min(0).max(1).optional(),
    lastAssessedAt: common_1.isoDateTimeSchema.optional(),
    sources: zod_1.z.array(exports.aptitudeSourceDto).optional(),
});
exports.skillPassportSkillDto = zod_1.z.object({
    name: zod_1.z.string().trim().min(1).max(200),
    category: zod_1.z.string().trim().max(100).optional(),
    level: zod_1.z.number().min(0).max(10).optional(),
    lastUsedAt: zod_1.z.string().trim().max(50).optional(),
    evidence: zod_1.z.array(zod_1.z.string().trim().max(100)).optional(),
});
exports.skillPassportCertificationDto = zod_1.z.object({
    name: zod_1.z.string().trim().min(1).max(200),
    issuer: zod_1.z.string().trim().max(200).optional(),
    issuedAt: zod_1.z.string().trim().max(50).optional(),
    expiresAt: zod_1.z.string().trim().max(50).nullable().optional(),
    id: zod_1.z.string().trim().max(100).optional(),
});
exports.aptivioProfileIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.assessmentRunIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.aptivioProfileInitDto = zod_1.z.object({
    primaryRole: zod_1.z.string().trim().max(120).optional(),
    roleFamily: zod_1.z.string().trim().max(120).optional(),
    seniority: zod_1.z.string().trim().max(50).optional(),
    country: zod_1.z.string().trim().length(2).optional(),
    sourceSystem: zod_1.z.string().trim().max(120).optional(),
    tags: zod_1.z.array(zod_1.z.string().trim().max(50)).optional(),
    twinJson: common_1.jsonObjectSchema.optional(),
});
exports.updateAptivioProfileStatusDto = zod_1.z.object({
    status: zod_1.z.enum(enums_1.aptivioProfileStatusValues),
});
exports.startAssessmentDto = zod_1.z.object({
    assessmentType: zod_1.z.string().trim().min(1).max(100),
    context: common_1.jsonObjectSchema.optional(),
});
exports.completeAssessmentDto = zod_1.z.object({
    rawResultJson: common_1.jsonObjectSchema.optional(),
    normalizedJson: common_1.jsonObjectSchema.optional(),
    aptitudes: zod_1.z.array(exports.aptitudeScoreDto).min(1).max(25),
    skillPassport: zod_1.z
        .object({
        skills: zod_1.z.array(exports.skillPassportSkillDto).optional(),
        certifications: zod_1.z.array(exports.skillPassportCertificationDto).optional(),
    })
        .optional(),
    professionalism: zod_1.z
        .object({
        overallScore: zod_1.z.number().int().min(0).max(100).optional(),
        lastUpdatedAt: common_1.isoDateTimeSchema.optional(),
        signals: zod_1.z.record(zod_1.z.string(), zod_1.z.number().min(0).max(100)).optional(),
    })
        .optional(),
    trajectory: zod_1.z
        .object({
        aptitudeTrend: zod_1.z.enum(["improving", "stable", "declining", "unknown"]).optional(),
        skillGrowthRate: zod_1.z.number().optional(),
        window: zod_1.z.string().trim().max(50).optional(),
    })
        .optional(),
    riskProfile: zod_1.z
        .object({
        humanCapitalRiskScore: zod_1.z.number().min(0).max(1).optional(),
        notes: zod_1.z.string().trim().max(1000).optional(),
        assessedAt: common_1.isoDateTimeSchema.optional(),
    })
        .optional(),
    twinJson: common_1.jsonObjectSchema.optional(),
});
exports.issueAptivioIdentityDto = zod_1.z.object({
    passportNumber: zod_1.z.string().trim().min(4).max(64),
    status: zod_1.z.string().trim().min(1).max(50).default("ACTIVE"),
    claimsJson: common_1.jsonObjectSchema.optional(),
    tokenEntitlementsJson: common_1.jsonObjectSchema.optional(),
});
exports.updateDigitalTwinPreferencesDto = zod_1.z.object({
    routinePreferences: common_1.jsonObjectSchema.optional(),
    characterGoals: zod_1.z.array(zod_1.z.string().trim().max(100)).optional(),
    learningGoals: zod_1.z.array(zod_1.z.string().trim().max(100)).optional(),
    privacyLevel: zod_1.z.enum(["private", "restricted", "public_summary"]).optional(),
    extensionsJson: common_1.jsonObjectSchema.optional(),
});
