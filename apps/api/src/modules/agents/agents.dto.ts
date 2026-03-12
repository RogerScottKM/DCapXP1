import { z } from "zod";
import {
  cuidSchema,
  isoDateTimeSchema,
  jsonObjectSchema,
  nonNegativeIntegerStringSchema,
} from "../../lib/dto/common";
import {
  agentCapabilityTierValues,
  agentCredentialTypeValues,
  agentKindValues,
  agentPrincipalTypeValues,
  agentStatusValues,
  mandateActionValues,
  mandateStatusValues,
} from "../../lib/dto/enums";

export const agentIdParamDto = z.object({
  id: cuidSchema,
});

export const agentKeyIdParamDto = z.object({
  id: cuidSchema,
});

export const mandateIdParamDto = z.object({
  id: cuidSchema,
});

export const createAgentDto = z.object({
  name: z.string().trim().min(1).max(120),
  principalType: z.enum(agentPrincipalTypeValues).optional(),
  kind: z.enum(agentKindValues),
  capabilityTier: z.enum(agentCapabilityTierValues).default("READ_ONLY"),
  version: z.string().trim().max(30).optional(),
  config: jsonObjectSchema.optional(),
  aptivioTokenId: z.string().trim().max(100).optional(),
});

export const updateAgentDto = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  principalType: z.enum(agentPrincipalTypeValues).optional(),
  kind: z.enum(agentKindValues).optional(),
  capabilityTier: z.enum(agentCapabilityTierValues).optional(),
  status: z.enum(agentStatusValues).optional(),
  version: z.string().trim().max(30).optional(),
  config: jsonObjectSchema.optional(),
  aptivioTokenId: z.string().trim().max(100).optional(),
});

export const createAgentKeyDto = z.discriminatedUnion("credentialType", [
  z.object({
    credentialType: z.literal("PUBLIC_KEY"),
    publicKeyPem: z.string().trim().min(32),
    expiresAt: isoDateTimeSchema.optional(),
  }),
  z.object({
    credentialType: z.literal("API_KEY"),
    keyPrefix: z.string().trim().min(4).max(20),
    keyHash: z.string().trim().min(16).max(255),
    expiresAt: isoDateTimeSchema.optional(),
  }),
]);

export const revokeAgentKeyDto = z.object({
  revokedAt: isoDateTimeSchema.optional(),
});

export const grantMandateDto = z.object({
  action: z.enum(mandateActionValues),
  market: z.string().trim().max(50).optional(),
  maxNotionalPerDay: nonNegativeIntegerStringSchema.default("0"),
  maxOrdersPerDay: z.number().int().min(0).default(0),
  notBefore: isoDateTimeSchema.optional(),
  expiresAt: isoDateTimeSchema,
  constraints: jsonObjectSchema.optional(),
  mandateJwtHash: z.string().trim().max(255).optional(),
});

export const updateMandateDto = z.object({
  status: z.enum(mandateStatusValues).optional(),
  market: z.string().trim().max(50).optional(),
  maxNotionalPerDay: nonNegativeIntegerStringSchema.optional(),
  maxOrdersPerDay: z.number().int().min(0).optional(),
  notBefore: isoDateTimeSchema.optional(),
  expiresAt: isoDateTimeSchema.optional(),
  constraints: jsonObjectSchema.optional(),
  mandateJwtHash: z.string().trim().max(255).optional(),
});

export type CreateAgentDto = z.infer<typeof createAgentDto>;
export type UpdateAgentDto = z.infer<typeof updateAgentDto>;
export type CreateAgentKeyDto = z.infer<typeof createAgentKeyDto>;
export type RevokeAgentKeyDto = z.infer<typeof revokeAgentKeyDto>;
export type GrantMandateDto = z.infer<typeof grantMandateDto>;
export type UpdateMandateDto = z.infer<typeof updateMandateDto>;
