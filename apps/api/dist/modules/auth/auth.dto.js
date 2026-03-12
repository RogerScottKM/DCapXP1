"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mfaVerifyDto = exports.mfaSetupDto = exports.resetPasswordDto = exports.requestPasswordResetDto = exports.loginDto = exports.setPasswordDto = exports.verifyOtpDto = exports.requestOtpDto = exports.registerDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
const enums_1 = require("../../lib/dto/enums");
exports.registerDto = zod_1.z.object({
    firstName: zod_1.z.string().trim().min(1).max(100),
    lastName: zod_1.z.string().trim().min(1).max(100),
    username: common_1.usernameSchema,
    email: common_1.emailSchema,
    phone: common_1.phoneSchema.optional(),
    country: zod_1.z.string().trim().length(2).optional(),
    sourceChannel: zod_1.z.string().trim().max(100).optional(),
});
exports.requestOtpDto = zod_1.z.object({
    target: zod_1.z.string().trim().min(3).max(320),
    purpose: zod_1.z.enum(enums_1.otpPurposeValues),
    channel: zod_1.z.enum(enums_1.otpChannelValues),
    userId: zod_1.z.string().cuid().optional(),
});
exports.verifyOtpDto = zod_1.z.object({
    target: zod_1.z.string().trim().min(3).max(320),
    code: common_1.otpCodeSchema,
    purpose: zod_1.z.enum(enums_1.otpPurposeValues),
});
exports.setPasswordDto = zod_1.z.object({
    email: common_1.emailSchema,
    password: common_1.passwordSchema,
});
exports.loginDto = zod_1.z.object({
    emailOrUsername: zod_1.z.string().trim().min(1).max(320),
    password: zod_1.z.string().min(1).max(128),
    otpCode: common_1.otpCodeSchema.optional(),
});
exports.requestPasswordResetDto = zod_1.z.object({
    email: common_1.emailSchema,
});
exports.resetPasswordDto = zod_1.z.object({
    email: common_1.emailSchema,
    otpCode: common_1.otpCodeSchema,
    newPassword: common_1.passwordSchema,
});
exports.mfaSetupDto = zod_1.z.object({
    label: zod_1.z.string().trim().min(1).max(100).optional(),
});
exports.mfaVerifyDto = zod_1.z.object({
    code: common_1.otpCodeSchema,
});
