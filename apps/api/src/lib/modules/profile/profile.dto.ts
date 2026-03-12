import { z } from "zod";
import {
  addressSchema,
  countryCodeSchema,
  isoDateTimeSchema,
  phoneSchema,
  jsonObjectSchema,
} from "../../lib/dto/common";

export const updateProfileDto = z.object({
  firstName: z.string().trim().min(1).max(100).optional(),
  lastName: z.string().trim().min(1).max(100).optional(),
  fullName: z.string().trim().max(200).optional(),
  dateOfBirth: isoDateTimeSchema.optional(),
  country: countryCodeSchema.optional(),
  residency: countryCodeSchema.optional(),
  nationality: countryCodeSchema.optional(),
  employerName: z.string().trim().max(200).optional(),
  sourceChannel: z.string().trim().max(100).optional(),
  address: addressSchema.partial().optional(),
});

export const updateContactDto = z.object({
  phone: phoneSchema.optional(),
});

export const acceptConsentDto = z.object({
  consentType: z.string().trim().min(1).max(100),
  version: z.string().trim().min(1).max(50),
  metadata: jsonObjectSchema.optional(),
});

export type UpdateProfileDto = z.infer<typeof updateProfileDto>;
export type UpdateContactDto = z.infer<typeof updateContactDto>;
export type AcceptConsentDto = z.infer<typeof acceptConsentDto>;
