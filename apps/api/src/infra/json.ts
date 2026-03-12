import { Decimal } from "@prisma/client/runtime/library";

export const jsonReplacer = (_k: string, v: any) => {
  if (typeof v === "bigint") return v.toString();
  if (v instanceof Decimal) return v.toString();
  return v;
};

export const safeStringify = (obj: unknown) => JSON.stringify(obj, jsonReplacer);
