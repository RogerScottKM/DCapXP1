"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.auditEventsQueryDto = exports.assignRoleDto = exports.createAdvisorProfileDto = exports.updatePartnerOrganizationDto = exports.createPartnerOrganizationDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
const enums_1 = require("../../lib/dto/enums");
exports.createPartnerOrganizationDto = zod_1.z.object({
    name: zod_1.z.string().trim().min(1).max(200),
    type: zod_1.z.enum(enums_1.partnerOrgTypeValues),
    country: zod_1.z.string().trim().length(2).optional(),
    metadata: common_1.jsonObjectSchema.optional(),
});
exports.updatePartnerOrganizationDto = zod_1.z.object({
    name: zod_1.z.string().trim().min(1).max(200).optional(),
    country: zod_1.z.string().trim().length(2).optional(),
    metadata: common_1.jsonObjectSchema.optional(),
});
exports.createAdvisorProfileDto = zod_1.z.object({
    userId: common_1.cuidSchema,
    organizationId: common_1.cuidSchema.optional(),
    licenseNumber: zod_1.z.string().trim().max(100).optional(),
    status: zod_1.z.string().trim().max(50).optional(),
    specialties: common_1.jsonObjectSchema.optional(),
});
exports.assignRoleDto = zod_1.z.object({
    userId: common_1.cuidSchema,
    roleCode: zod_1.z.enum(enums_1.roleCodeValues),
    scopeType: zod_1.z.string().trim().max(100).optional(),
    scopeId: zod_1.z.string().trim().max(100).optional(),
});
exports.auditEventsQueryDto = common_1.paginationQuerySchema.extend({
    actorType: zod_1.z.string().trim().max(100).optional(),
    actorId: zod_1.z.string().trim().max(100).optional(),
    action: zod_1.z.string().trim().max(100).optional(),
    resourceType: zod_1.z.string().trim().max(100).optional(),
    resourceId: zod_1.z.string().trim().max(100).optional(),
});
