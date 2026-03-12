"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.acceptConsentDto = exports.updateContactDto = exports.updateProfileDto = void 0;
const zod_1 = require("zod");
const common_1 = require("../../lib/dto/common");
exports.updateProfileDto = zod_1.z.object({
    firstName: zod_1.z.string().trim().min(1).max(100).optional(),
    lastName: zod_1.z.string().trim().min(1).max(100).optional(),
    fullName: zod_1.z.string().trim().max(200).optional(),
    dateOfBirth: common_1.isoDateTimeSchema.optional(),
    country: common_1.countryCodeSchema.optional(),
    residency: common_1.countryCodeSchema.optional(),
    nationality: common_1.countryCodeSchema.optional(),
    employerName: zod_1.z.string().trim().max(200).optional(),
    sourceChannel: zod_1.z.string().trim().max(100).optional(),
    address: common_1.addressSchema.partial().optional(),
});
exports.updateContactDto = zod_1.z.object({
    phone: common_1.phoneSchema.optional(),
});
exports.acceptConsentDto = zod_1.z.object({
    consentType: zod_1.z.string().trim().min(1).max(100),
    version: zod_1.z.string().trim().min(1).max(50),
    metadata: common_1.jsonObjectSchema.optional(),
});
