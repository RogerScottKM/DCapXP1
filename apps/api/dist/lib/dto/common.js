"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.addressSchema = exports.cuidParamDto = exports.paginationQuerySchema = exports.nonNegativeDecimalStringSchema = exports.decimalStringSchema = exports.nonNegativeIntegerStringSchema = exports.jsonObjectSchema = exports.currencyCodeSchema = exports.countryCodeSchema = exports.otpCodeSchema = exports.passwordSchema = exports.usernameSchema = exports.phoneSchema = exports.emailSchema = exports.isoDateTimeSchema = exports.cuidSchema = void 0;
const zod_1 = require("zod");
exports.cuidSchema = zod_1.z.string().cuid();
exports.isoDateTimeSchema = zod_1.z.string().datetime();
exports.emailSchema = zod_1.z.string().trim().toLowerCase().email();
exports.phoneSchema = zod_1.z.string().trim().min(6).max(32);
exports.usernameSchema = zod_1.z
    .string()
    .trim()
    .min(3)
    .max(50)
    .regex(/^[a-zA-Z0-9._-]+$/, "Username may contain letters, numbers, dot, underscore, hyphen only");
exports.passwordSchema = zod_1.z
    .string()
    .min(12, "Password must be at least 12 characters")
    .max(128)
    .regex(/[A-Z]/, "Password must contain an uppercase letter")
    .regex(/[a-z]/, "Password must contain a lowercase letter")
    .regex(/[0-9]/, "Password must contain a number")
    .regex(/[^A-Za-z0-9]/, "Password must contain a symbol");
exports.otpCodeSchema = zod_1.z.string().trim().regex(/^\d{6}$/, "OTP code must be 6 digits");
exports.countryCodeSchema = zod_1.z
    .string()
    .trim()
    .length(2)
    .regex(/^[A-Za-z]{2}$/, "Country code must be ISO alpha-2");
exports.currencyCodeSchema = zod_1.z
    .string()
    .trim()
    .length(3)
    .regex(/^[A-Za-z]{3}$/, "Currency code must be ISO 4217 alpha-3");
exports.jsonObjectSchema = zod_1.z.record(zod_1.z.string(), zod_1.z.unknown());
exports.nonNegativeIntegerStringSchema = zod_1.z
    .string()
    .trim()
    .regex(/^\d+$/, "Must be a non-negative integer string");
exports.decimalStringSchema = zod_1.z
    .string()
    .trim()
    .regex(/^-?\d+(\.\d+)?$/, "Must be a decimal string");
exports.nonNegativeDecimalStringSchema = zod_1.z
    .string()
    .trim()
    .regex(/^\d+(\.\d+)?$/, "Must be a non-negative decimal string");
exports.paginationQuerySchema = zod_1.z.object({
    page: zod_1.z.coerce.number().int().min(1).default(1),
    pageSize: zod_1.z.coerce.number().int().min(1).max(100).default(20),
});
exports.cuidParamDto = zod_1.z.object({
    id: exports.cuidSchema,
});
exports.addressSchema = zod_1.z.object({
    addressLine1: zod_1.z.string().trim().min(1).max(200),
    addressLine2: zod_1.z.string().trim().max(200).optional(),
    city: zod_1.z.string().trim().min(1).max(120),
    state: zod_1.z.string().trim().max(120).optional(),
    postalCode: zod_1.z.string().trim().max(40).optional(),
    country: exports.countryCodeSchema,
});
