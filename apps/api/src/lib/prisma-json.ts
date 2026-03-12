import { Prisma } from "@prisma/client";

export function asJson(
  value: unknown,
): Prisma.InputJsonValue | Prisma.NullableJsonNullValueInput | undefined {
  return value === undefined ? undefined : (value as Prisma.InputJsonValue);
}
