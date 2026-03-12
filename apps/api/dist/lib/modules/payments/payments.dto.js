"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.adminUpdatePaymentMethodStatusDto = exports.updateOwnPaymentMethodDto = exports.createPaymentMethodDto = exports.paymentMethodIdParamDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
const enums_1 = require("../../lib/dto/enums");
exports.paymentMethodIdParamDto = zod_1.z.object({
    id: common_1.cuidSchema,
});
exports.createPaymentMethodDto = zod_1.z.discriminatedUnion("type", [
    zod_1.z.object({
        type: zod_1.z.literal("BANK_ACCOUNT"),
        label: zod_1.z.string().trim().max(100).optional(),
        bankAccount: zod_1.z.object({
            accountHolderName: zod_1.z.string().trim().min(1).max(200),
            bankName: zod_1.z.string().trim().min(1).max(200),
            country: common_1.countryCodeSchema,
            currency: common_1.currencyCodeSchema.optional(),
            maskedAccountNumber: zod_1.z.string().trim().min(2).max(64).optional(),
            maskedRoutingNumber: zod_1.z.string().trim().min(2).max(64).optional(),
            ibanMasked: zod_1.z.string().trim().max(64).optional(),
            swiftBicMasked: zod_1.z.string().trim().max(64).optional(),
            metadata: common_1.jsonObjectSchema.optional(),
        }),
        metadata: common_1.jsonObjectSchema.optional(),
    }),
    zod_1.z.object({
        type: zod_1.z.literal("STRIPE_CUSTOMER"),
        label: zod_1.z.string().trim().max(100).optional(),
        metadata: common_1.jsonObjectSchema.optional(),
    }),
    zod_1.z.object({
        type: zod_1.z.literal("PAYPAL_ACCOUNT"),
        label: zod_1.z.string().trim().max(100).optional(),
        metadata: common_1.jsonObjectSchema.optional(),
    }),
    zod_1.z.object({
        type: zod_1.z.literal("VENMO_ACCOUNT"),
        label: zod_1.z.string().trim().max(100).optional(),
        metadata: common_1.jsonObjectSchema.optional(),
    }),
    zod_1.z.object({
        type: zod_1.z.literal("OTHER"),
        label: zod_1.z.string().trim().max(100).optional(),
        metadata: common_1.jsonObjectSchema.optional(),
    }),
]);
exports.updateOwnPaymentMethodDto = zod_1.z.object({
    label: zod_1.z.string().trim().max(100).optional(),
    metadata: common_1.jsonObjectSchema.optional(),
});
exports.adminUpdatePaymentMethodStatusDto = zod_1.z.object({
    status: zod_1.z.enum(enums_1.paymentMethodStatusValues),
    metadata: common_1.jsonObjectSchema.optional(),
});
