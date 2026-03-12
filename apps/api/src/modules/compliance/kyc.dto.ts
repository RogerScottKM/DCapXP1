import { z } from "zod";
import {
  countryCodeSchema,
  cuidSchema,
  isoDateTimeSchema,
  jsonObjectSchema,
  nonNegativeDecimalStringSchema,
  paginationQuerySchema,
} from "../../lib/dto/common";
import {
  kycCaseStatusValues,
  kycDecisionCodeValues,
  kycDocumentTypeValues,
  kycStatusValues,
} from "../../lib/dto/enums";

// -------------------------
// New KycCase workflow DTOs
// -------------------------

export const kycCaseIdParamDto = z.object({
  id: cuidSchema,
});

export const createKycCaseDto = z.object({
  notes: z.string().trim().max(1000).optional(),
});

export const uploadKycDocumentDto = z.object({
  docType: z.enum(kycDocumentTypeValues),
  fileKey: z.string().trim().min(1).max(500),
  fileName: z.string().trim().max(255).optional(),
  mimeType: z.string().trim().max(100).optional(),
  metadata: jsonObjectSchema.optional(),
});

export const submitKycCaseDto = z.object({
  attestTruthfulness: z.literal(true),
});

export const adminKycCaseDecisionDto = z.object({
  decision: z.enum(kycDecisionCodeValues),
  reasonCode: z.string().trim().max(100).optional(),
  notes: z.string().trim().max(2000).optional(),
});

export const kycCaseQueueQueryDto = paginationQuerySchema.extend({
  status: z.enum(kycCaseStatusValues).optional(),
  userId: z.string().cuid().optional(),
});

// -------------------------
// Legacy summary Kyc DTO
// Keep this for backfill/compat routes only
// -------------------------

export const upsertLegacyKycDto = z.object({
  legalName: z.string().trim().min(1).max(200),
  country: countryCodeSchema,
  dob: isoDateTimeSchema,
  docType: z.string().trim().min(1).max(100),
  docHash: z.string().trim().min(8).max(255),
  status: z.enum(kycStatusValues).default("PENDING"),
  riskScore: nonNegativeDecimalStringSchema.optional(),
});

export type CreateKycCaseDto = z.infer<typeof createKycCaseDto>;
export type UploadKycDocumentDto = z.infer<typeof uploadKycDocumentDto>;
export type SubmitKycCaseDto = z.infer<typeof submitKycCaseDto>;
export type AdminKycCaseDecisionDto = z.infer<typeof adminKycCaseDecisionDto>;
export type KycCaseQueueQueryDto = z.infer<typeof kycCaseQueueQueryDto>;
export type UpsertLegacyKycDto = z.infer<typeof upsertLegacyKycDto>;
