import { z } from "zod";
import {
  emailSchema,
  otpCodeSchema,
  passwordSchema,
  phoneSchema,
  usernameSchema,
} from "../../lib/dto/common";
import {
  otpChannelValues,
  otpPurposeValues,
} from "../../lib/dto/enums";

export const registerDto = z.object({
  firstName: z.string().trim().min(1).max(100),
  lastName: z.string().trim().min(1).max(100),
  username: usernameSchema,
  email: emailSchema,
  phone: phoneSchema.optional(),
  country: z.string().trim().length(2).optional(),
  sourceChannel: z.string().trim().max(100).optional(),
});

export const requestOtpDto = z.object({
  target: z.string().trim().min(3).max(320),
  purpose: z.enum(otpPurposeValues),
  channel: z.enum(otpChannelValues),
  userId: z.string().cuid().optional(),
});

export const verifyOtpDto = z.object({
  target: z.string().trim().min(3).max(320),
  code: otpCodeSchema,
  purpose: z.enum(otpPurposeValues),
});

export const setPasswordDto = z.object({
  email: emailSchema,
  password: passwordSchema,
});

export const loginDto = z.object({
  emailOrUsername: z.string().trim().min(1).max(320),
  password: z.string().min(1).max(128),
  otpCode: otpCodeSchema.optional(),
});

export const requestPasswordResetDto = z.object({
  email: emailSchema,
});

export const resetPasswordDto = z.object({
  email: emailSchema,
  otpCode: otpCodeSchema,
  newPassword: passwordSchema,
});

export const mfaSetupDto = z.object({
  label: z.string().trim().min(1).max(100).optional(),
});

export const mfaVerifyDto = z.object({
  code: otpCodeSchema,
});

export type RegisterDto = z.infer<typeof registerDto>;
export type RequestOtpDto = z.infer<typeof requestOtpDto>;
export type VerifyOtpDto = z.infer<typeof verifyOtpDto>;
export type SetPasswordDto = z.infer<typeof setPasswordDto>;
export type LoginDto = z.infer<typeof loginDto>;
export type RequestPasswordResetDto = z.infer<typeof requestPasswordResetDto>;
export type ResetPasswordDto = z.infer<typeof resetPasswordDto>;
export type MfaSetupDto = z.infer<typeof mfaSetupDto>;
export type MfaVerifyDto = z.infer<typeof mfaVerifyDto>;
