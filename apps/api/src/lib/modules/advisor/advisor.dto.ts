import { z } from "zod";
import {
  cuidSchema,
  emailSchema,
  phoneSchema,
  usernameSchema,
  jsonObjectSchema,
} from "../../lib/dto/common";

export const advisorClientIdParamDto = z.object({
  id: cuidSchema,
});

export const inviteAdvisorClientDto = z.object({
  email: emailSchema,
  username: usernameSchema,
  firstName: z.string().trim().min(1).max(100).optional(),
  lastName: z.string().trim().min(1).max(100).optional(),
  phone: phoneSchema.optional(),
  sourceChannel: z.string().trim().max(100).optional(),
  notes: z.string().trim().max(1000).optional(),
});

export const updateAdvisorClientAssignmentStatusDto = z.object({
  status: z.string().trim().min(1).max(50),
  notes: z.string().trim().max(1000).optional(),
});

export const advisorClientNoteDto = z.object({
  note: z.string().trim().min(1).max(5000),
});

export const advisorClientPlanDto = z.object({
  title: z.string().trim().min(1).max(200),
  summary: z.string().trim().min(1).max(4000),
  planJson: jsonObjectSchema.optional(),
});

export type InviteAdvisorClientDto = z.infer<typeof inviteAdvisorClientDto>;
export type UpdateAdvisorClientAssignmentStatusDto = z.infer<typeof updateAdvisorClientAssignmentStatusDto>;
export type AdvisorClientNoteDto = z.infer<typeof advisorClientNoteDto>;
export type AdvisorClientPlanDto = z.infer<typeof advisorClientPlanDto>;

