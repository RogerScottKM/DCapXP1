import { z } from "zod";
import {
  cuidSchema,
  isoDateTimeSchema,
  jsonObjectSchema,
} from "../../lib/dto/common";
import {
  aptivioProfileStatusValues,
} from "../../lib/dto/enums";

export const aptitudeSourceDto = z.object({
  type: z.enum([
    "simulation",
    "assessment",
    "manager_review",
    "peer_review",
    "work_artefact",
    "other",
  ]),
  refId: z.string().trim().max(100).optional(),
  weight: z.number().min(0).max(1).optional(),
});

export const aptitudeScoreDto = z.object({
  id: z.string().trim().min(1).max(100),
  name: z.string().trim().min(1).max(200),
  score: z.number().int().min(0).max(100),
  confidence: z.number().min(0).max(1).optional(),
  weightForRole: z.number().min(0).max(1).optional(),
  lastAssessedAt: isoDateTimeSchema.optional(),
  sources: z.array(aptitudeSourceDto).optional(),
});

export const skillPassportSkillDto = z.object({
  name: z.string().trim().min(1).max(200),
  category: z.string().trim().max(100).optional(),
  level: z.number().min(0).max(10).optional(),
  lastUsedAt: z.string().trim().max(50).optional(),
  evidence: z.array(z.string().trim().max(100)).optional(),
});

export const skillPassportCertificationDto = z.object({
  name: z.string().trim().min(1).max(200),
  issuer: z.string().trim().max(200).optional(),
  issuedAt: z.string().trim().max(50).optional(),
  expiresAt: z.string().trim().max(50).nullable().optional(),
  id: z.string().trim().max(100).optional(),
});

export const aptivioProfileIdParamDto = z.object({
  id: cuidSchema,
});

export const assessmentRunIdParamDto = z.object({
  id: cuidSchema,
});

export const aptivioProfileInitDto = z.object({
  primaryRole: z.string().trim().max(120).optional(),
  roleFamily: z.string().trim().max(120).optional(),
  seniority: z.string().trim().max(50).optional(),
  country: z.string().trim().length(2).optional(),
  sourceSystem: z.string().trim().max(120).optional(),
  tags: z.array(z.string().trim().max(50)).optional(),
  twinJson: jsonObjectSchema.optional(),
});

export const updateAptivioProfileStatusDto = z.object({
  status: z.enum(aptivioProfileStatusValues),
});

export const startAssessmentDto = z.object({
  assessmentType: z.string().trim().min(1).max(100),
  context: jsonObjectSchema.optional(),
});

export const completeAssessmentDto = z.object({
  rawResultJson: jsonObjectSchema.optional(),
  normalizedJson: jsonObjectSchema.optional(),
  aptitudes: z.array(aptitudeScoreDto).min(1).max(25),
  skillPassport: z
    .object({
      skills: z.array(skillPassportSkillDto).optional(),
      certifications: z.array(skillPassportCertificationDto).optional(),
    })
    .optional(),
  professionalism: z
    .object({
      overallScore: z.number().int().min(0).max(100).optional(),
      lastUpdatedAt: isoDateTimeSchema.optional(),
      signals: z.record(z.string(), z.number().min(0).max(100)).optional(),
    })
    .optional(),
  trajectory: z
    .object({
      aptitudeTrend: z.enum(["improving", "stable", "declining", "unknown"]).optional(),
      skillGrowthRate: z.number().optional(),
      window: z.string().trim().max(50).optional(),
    })
    .optional(),
  riskProfile: z
    .object({
      humanCapitalRiskScore: z.number().min(0).max(1).optional(),
      notes: z.string().trim().max(1000).optional(),
      assessedAt: isoDateTimeSchema.optional(),
    })
    .optional(),
  twinJson: jsonObjectSchema.optional(),
});

export const issueAptivioIdentityDto = z.object({
  passportNumber: z.string().trim().min(4).max(64),
  status: z.string().trim().min(1).max(50).default("ACTIVE"),
  claimsJson: jsonObjectSchema.optional(),
  tokenEntitlementsJson: jsonObjectSchema.optional(),
});

export const updateDigitalTwinPreferencesDto = z.object({
  routinePreferences: jsonObjectSchema.optional(),
  characterGoals: z.array(z.string().trim().max(100)).optional(),
  learningGoals: z.array(z.string().trim().max(100)).optional(),
  privacyLevel: z.enum(["private", "restricted", "public_summary"]).optional(),
  extensionsJson: jsonObjectSchema.optional(),
});

export type AptivioProfileInitDto = z.infer<typeof aptivioProfileInitDto>;
export type UpdateAptivioProfileStatusDto = z.infer<typeof updateAptivioProfileStatusDto>;
export type StartAssessmentDto = z.infer<typeof startAssessmentDto>;
export type CompleteAssessmentDto = z.infer<typeof completeAssessmentDto>;
export type IssueAptivioIdentityDto = z.infer<typeof issueAptivioIdentityDto>;
export type UpdateDigitalTwinPreferencesDto = z.infer<typeof updateDigitalTwinPreferencesDto>;
