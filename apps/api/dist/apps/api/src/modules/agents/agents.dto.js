"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateMandateDto = exports.grantMandateDto = exports.revokeAgentKeyDto = exports.createAgentKeyDto = exports.updateAgentDto = exports.createAgentDto = exports.mandateIdParamDto = exports.agentKeyIdParamDto = exports.agentIdParamDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
const enums_1 = require("../../lib/dto/enums");
exports.agentIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.agentKeyIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.mandateIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.createAgentDto = zod_1.z.object({
    name: zod_1.z.string().trim().min(1).max(120),
    principalType: zod_1.z.enum(enums_1.agentPrincipalTypeValues).optional(),
    kind: zod_1.z.enum(enums_1.agentKindValues),
    capabilityTier: zod_1.z.enum(enums_1.agentCapabilityTierValues).default("READ_ONLY"),
    version: zod_1.z.string().trim().max(30).optional(),
    config: common_1.jsonObjectSchema.optional(),
    aptivioTokenId: zod_1.z.string().trim().max(100).optional(),
});
exports.updateAgentDto = zod_1.z.object({
    name: zod_1.z.string().trim().min(1).max(120).optional(),
    principalType: zod_1.z.enum(enums_1.agentPrincipalTypeValues).optional(),
    kind: zod_1.z.enum(enums_1.agentKindValues).optional(),
    capabilityTier: zod_1.z.enum(enums_1.agentCapabilityTierValues).optional(),
    status: zod_1.z.enum(enums_1.agentStatusValues).optional(),
    version: zod_1.z.string().trim().max(30).optional(),
    config: common_1.jsonObjectSchema.optional(),
    aptivioTokenId: zod_1.z.string().trim().max(100).optional(),
});
exports.createAgentKeyDto = zod_1.z.discriminatedUnion("credentialType", [
    zod_1.z.object({
        credentialType: zod_1.z.literal("PUBLIC_KEY"),
        publicKeyPem: zod_1.z.string().trim().min(32),
        expiresAt: common_1.isoDateTimeSchema.optional(),
    }),
    zod_1.z.object({
        credentialType: zod_1.z.literal("API_KEY"),
        keyPrefix: zod_1.z.string().trim().min(4).max(20),
        keyHash: zod_1.z.string().trim().min(16).max(255),
        expiresAt: common_1.isoDateTimeSchema.optional(),
    }),
]);
exports.revokeAgentKeyDto = zod_1.z.object({
    revokedAt: common_1.isoDateTimeSchema.optional(),
});
exports.grantMandateDto = zod_1.z.object({
    action: zod_1.z.enum(enums_1.mandateActionValues),
    market: zod_1.z.string().trim().max(50).optional(),
    maxNotionalPerDay: common_1.nonNegativeIntegerStringSchema.default("0"),
    maxOrdersPerDay: zod_1.z.number().int().min(0).default(0),
    notBefore: common_1.isoDateTimeSchema.optional(),
    expiresAt: common_1.isoDateTimeSchema,
    constraints: common_1.jsonObjectSchema.optional(),
    mandateJwtHash: zod_1.z.string().trim().max(255).optional(),
});
exports.updateMandateDto = zod_1.z.object({
    status: zod_1.z.enum(enums_1.mandateStatusValues).optional(),
    market: zod_1.z.string().trim().max(50).optional(),
    maxNotionalPerDay: common_1.nonNegativeIntegerStringSchema.optional(),
    maxOrdersPerDay: zod_1.z.number().int().min(0).optional(),
    notBefore: common_1.isoDateTimeSchema.optional(),
    expiresAt: common_1.isoDateTimeSchema.optional(),
    constraints: common_1.jsonObjectSchema.optional(),
    mandateJwtHash: zod_1.z.string().trim().max(255).optional(),
});
