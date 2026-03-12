import { ZodSchema } from "zod";

export function parseDto<T>(schema: ZodSchema<T>, input: unknown): T {
  return schema.parse(input);
}
