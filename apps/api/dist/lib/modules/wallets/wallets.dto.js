"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.adminUpdateWalletWhitelistStatusDto = exports.adminUpdateWalletStatusDto = exports.createWalletWhitelistEntryDto = exports.updateOwnWalletDto = exports.createWalletDto = exports.whitelistEntryIdParamDto = exports.walletIdParamDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
const enums_1 = require("../../lib/dto/enums");
exports.walletIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.whitelistEntryIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.createWalletDto = zod_1.z.discriminatedUnion("type", [
    zod_1.z.object({
        type: zod_1.z.literal("CUSTODIAL"),
        label: zod_1.z.string().trim().max(100).optional(),
        metadata: common_1.jsonObjectSchema.optional(),
    }),
    zod_1.z.object({
        type: zod_1.z.literal("EXTERNAL"),
        chain: zod_1.z.string().trim().min(1).max(50),
        address: zod_1.z.string().trim().min(3).max(255),
        label: zod_1.z.string().trim().max(100).optional(),
        metadata: common_1.jsonObjectSchema.optional(),
    }),
]);
exports.updateOwnWalletDto = zod_1.z.object({
    label: zod_1.z.string().trim().max(100).optional(),
    metadata: common_1.jsonObjectSchema.optional(),
});
exports.createWalletWhitelistEntryDto = zod_1.z.object({
    chain: zod_1.z.string().trim().min(1).max(50),
    address: zod_1.z.string().trim().min(3).max(255),
    label: zod_1.z.string().trim().max(100).optional(),
});
exports.adminUpdateWalletStatusDto = zod_1.z.object({
    status: zod_1.z.enum(enums_1.walletStatusValues),
    label: zod_1.z.string().trim().max(100).optional(),
});
exports.adminUpdateWalletWhitelistStatusDto = zod_1.z.object({
    status: zod_1.z.enum(enums_1.walletStatusValues),
    label: zod_1.z.string().trim().max(100).optional(),
});
