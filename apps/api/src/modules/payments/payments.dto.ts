import { z } from "zod";
import {
  countryCodeSchema,
  cuidSchema,
  currencyCodeSchema,
  jsonObjectSchema,
} from "../../lib/dto/common";
import {
  paymentMethodStatusValues,
} from "../../lib/dto/enums";

export const paymentMethodIdParamDto = z.object({
  id: cuidSchema,
});

export const createPaymentMethodDto = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("BANK_ACCOUNT"),
    label: z.string().trim().max(100).optional(),
    bankAccount: z.object({
      accountHolderName: z.string().trim().min(1).max(200),
      bankName: z.string().trim().min(1).max(200),
      country: countryCodeSchema,
      currency: currencyCodeSchema.optional(),
      maskedAccountNumber: z.string().trim().min(2).max(64).optional(),
      maskedRoutingNumber: z.string().trim().min(2).max(64).optional(),
      ibanMasked: z.string().trim().max(64).optional(),
      swiftBicMasked: z.string().trim().max(64).optional(),
      metadata: jsonObjectSchema.optional(),
    }),
    metadata: jsonObjectSchema.optional(),
  }),
  z.object({
    type: z.literal("STRIPE_CUSTOMER"),
    label: z.string().trim().max(100).optional(),
    metadata: jsonObjectSchema.optional(),
  }),
  z.object({
    type: z.literal("PAYPAL_ACCOUNT"),
    label: z.string().trim().max(100).optional(),
    metadata: jsonObjectSchema.optional(),
  }),
  z.object({
    type: z.literal("VENMO_ACCOUNT"),
    label: z.string().trim().max(100).optional(),
    metadata: jsonObjectSchema.optional(),
  }),
  z.object({
    type: z.literal("OTHER"),
    label: z.string().trim().max(100).optional(),
    metadata: jsonObjectSchema.optional(),
  }),
]);

export const updateOwnPaymentMethodDto = z.object({
  label: z.string().trim().max(100).optional(),
  metadata: jsonObjectSchema.optional(),
});

export const adminUpdatePaymentMethodStatusDto = z.object({
  status: z.enum(paymentMethodStatusValues),
  metadata: jsonObjectSchema.optional(),
});

export type CreatePaymentMethodDto = z.infer<typeof createPaymentMethodDto>;
export type UpdateOwnPaymentMethodDto = z.infer<typeof updateOwnPaymentMethodDto>;
export type AdminUpdatePaymentMethodStatusDto = z.infer<typeof adminUpdatePaymentMethodStatusDto>;
