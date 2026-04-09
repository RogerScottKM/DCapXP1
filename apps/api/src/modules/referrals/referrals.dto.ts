import { z } from "zod";

export const referralApplySourceSchema = z.enum([
  "LOGIN",
  "ONBOARDING",
  "INVITATION",
  "REGISTER",
  "ADMIN",
  "IMPORT",
]);

export const applyReferralCodeDto = z.object({
  code: z.string().trim().min(3).max(64),
  applySource: referralApplySourceSchema.optional().default("ONBOARDING"),
});

export type ApplyReferralCodeDto = z.infer<typeof applyReferralCodeDto>;
