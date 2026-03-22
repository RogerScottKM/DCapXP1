"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.advisorClientPlanDto = exports.advisorClientNoteDto = exports.updateAdvisorClientAssignmentStatusDto = exports.inviteAdvisorClientDto = exports.advisorClientIdParamDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
exports.advisorClientIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.inviteAdvisorClientDto = zod_1.z.object({
    email: common_1.emailSchema,
    username: common_1.usernameSchema,
    firstName: zod_1.z.string().trim().min(1).max(100).optional(),
    lastName: zod_1.z.string().trim().min(1).max(100).optional(),
    phone: common_1.phoneSchema.optional(),
    sourceChannel: zod_1.z.string().trim().max(100).optional(),
    notes: zod_1.z.string().trim().max(1000).optional(),
});
exports.updateAdvisorClientAssignmentStatusDto = zod_1.z.object({
    status: zod_1.z.string().trim().min(1).max(50),
    notes: zod_1.z.string().trim().max(1000).optional(),
});
exports.advisorClientNoteDto = zod_1.z.object({
    note: zod_1.z.string().trim().min(1).max(5000),
});
exports.advisorClientPlanDto = zod_1.z.object({
    title: zod_1.z.string().trim().min(1).max(200),
    summary: zod_1.z.string().trim().min(1).max(4000),
    planJson: common_1.jsonObjectSchema.optional(),
});
