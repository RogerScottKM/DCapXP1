"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.applyReferralCodeDto = exports.referralApplySourceSchema = void 0;
const zod_1 = require("zod");
exports.referralApplySourceSchema = zod_1.z.enum([
    "LOGIN",
    "ONBOARDING",
    "INVITATION",
    "REGISTER",
    "ADMIN",
    "IMPORT",
]);
exports.applyReferralCodeDto = zod_1.z.object({
    code: zod_1.z.string().trim().min(3).max(64),
    applySource: exports.referralApplySourceSchema.optional().default("ONBOARDING"),
});
