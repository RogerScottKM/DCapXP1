import { z } from "zod";
import {
  cuidSchema,
  jsonObjectSchema,
  paginationQuerySchema,
} from "../../lib/dto/common";
import {
  partnerOrgTypeValues,
  roleCodeValues,
} from "../../lib/dto/enums";

export const createPartnerOrganizationDto = z.object({
  name: z.string().trim().min(1).max(200),
  type: z.enum(partnerOrgTypeValues),
  country: z.string().trim().length(2).optional(),
  metadata: jsonObjectSchema.optional(),
});

export const updatePartnerOrganizationDto = z.object({
  name: z.string().trim().min(1).max(200).optional(),
  country: z.string().trim().length(2).optional(),
  metadata: jsonObjectSchema.optional(),
});

export const createAdvisorProfileDto = z.object({
  userId: cuidSchema,
  organizationId: cuidSchema.optional(),
  licenseNumber: z.string().trim().max(100).optional(),
  status: z.string().trim().max(50).optional(),
  specialties: jsonObjectSchema.optional(),
});

export const assignRoleDto = z.object({
  userId: cuidSchema,
  roleCode: z.enum(roleCodeValues),
  scopeType: z.string().trim().max(100).optional(),
  scopeId: z.string().trim().max(100).optional(),
});

export const auditEventsQueryDto = paginationQuerySchema.extend({
  actorType: z.string().trim().max(100).optional(),
  actorId: z.string().trim().max(100).optional(),
  action: z.string().trim().max(100).optional(),
  resourceType: z.string().trim().max(100).optional(),
  resourceId: z.string().trim().max(100).optional(),
});

export type CreatePartnerOrganizationDto = z.infer<typeof createPartnerOrganizationDto>;
export type UpdatePartnerOrganizationDto = z.infer<typeof updatePartnerOrganizationDto>;
export type CreateAdvisorProfileDto = z.infer<typeof createAdvisorProfileDto>;
export type AssignRoleDto = z.infer<typeof assignRoleDto>;
export type AuditEventsQueryDto = z.infer<typeof auditEventsQueryDto>;
