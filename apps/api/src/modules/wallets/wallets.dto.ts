import { z } from "zod";
import { cuidSchema, jsonObjectSchema } from "../../lib/dto/common";
import { walletStatusValues } from "../../lib/dto/enums";

export const walletIdParamDto = z.object({
  id: cuidSchema,
});

export const whitelistEntryIdParamDto = z.object({
  id: cuidSchema,
});

export const createWalletDto = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("CUSTODIAL"),
    label: z.string().trim().max(100).optional(),
    metadata: jsonObjectSchema.optional(),
  }),
  z.object({
    type: z.literal("EXTERNAL"),
    chain: z.string().trim().min(1).max(50),
    address: z.string().trim().min(3).max(255),
    label: z.string().trim().max(100).optional(),
    metadata: jsonObjectSchema.optional(),
  }),
]);

export const updateOwnWalletDto = z.object({
  label: z.string().trim().max(100).optional(),
  metadata: jsonObjectSchema.optional(),
});

export const createWalletWhitelistEntryDto = z.object({
  chain: z.string().trim().min(1).max(50),
  address: z.string().trim().min(3).max(255),
  label: z.string().trim().max(100).optional(),
});

export const adminUpdateWalletStatusDto = z.object({
  status: z.enum(walletStatusValues),
  label: z.string().trim().max(100).optional(),
});

export const adminUpdateWalletWhitelistStatusDto = z.object({
  status: z.enum(walletStatusValues),
  label: z.string().trim().max(100).optional(),
});

export type CreateWalletDto = z.infer<typeof createWalletDto>;
export type UpdateOwnWalletDto = z.infer<typeof updateOwnWalletDto>;
export type CreateWalletWhitelistEntryDto = z.infer<typeof createWalletWhitelistEntryDto>;
export type AdminUpdateWalletStatusDto = z.infer<typeof adminUpdateWalletStatusDto>;
export type AdminUpdateWalletWhitelistStatusDto = z.infer<typeof adminUpdateWalletWhitelistStatusDto>;
