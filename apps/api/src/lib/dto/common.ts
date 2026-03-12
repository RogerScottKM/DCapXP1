import { z } from "zod";

export const cuidSchema = z.string().cuid();
export const isoDateTimeSchema = z.string().datetime();
export const emailSchema = z.string().trim().toLowerCase().email();
export const phoneSchema = z.string().trim().min(6).max(32);

export const usernameSchema = z
  .string()
  .trim()
  .min(3)
  .max(50)
  .regex(/^[a-zA-Z0-9._-]+$/, "Username may contain letters, numbers, dot, underscore, hyphen only");

export const passwordSchema = z
  .string()
  .min(12, "Password must be at least 12 characters")
  .max(128)
  .regex(/[A-Z]/, "Password must contain an uppercase letter")
  .regex(/[a-z]/, "Password must contain a lowercase letter")
  .regex(/[0-9]/, "Password must contain a number")
  .regex(/[^A-Za-z0-9]/, "Password must contain a symbol");

export const otpCodeSchema = z.string().trim().regex(/^\d{6}$/, "OTP code must be 6 digits");

export const countryCodeSchema = z
  .string()
  .trim()
  .length(2)
  .regex(/^[A-Za-z]{2}$/, "Country code must be ISO alpha-2");

export const currencyCodeSchema = z
  .string()
  .trim()
  .length(3)
  .regex(/^[A-Za-z]{3}$/, "Currency code must be ISO 4217 alpha-3");

export const jsonObjectSchema = z.record(z.string(), z.unknown());

export const nonNegativeIntegerStringSchema = z
  .string()
  .trim()
  .regex(/^\d+$/, "Must be a non-negative integer string");

export const decimalStringSchema = z
  .string()
  .trim()
  .regex(/^-?\d+(\.\d+)?$/, "Must be a decimal string");

export const nonNegativeDecimalStringSchema = z
  .string()
  .trim()
  .regex(/^\d+(\.\d+)?$/, "Must be a non-negative decimal string");

export const paginationQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

export const cuidParamDto = z.object({
  id: cuidSchema,
});

export const addressSchema = z.object({
  addressLine1: z.string().trim().min(1).max(200),
  addressLine2: z.string().trim().max(200).optional(),
  city: z.string().trim().min(1).max(120),
  state: z.string().trim().max(120).optional(),
  postalCode: z.string().trim().max(40).optional(),
  country: countryCodeSchema,
});
