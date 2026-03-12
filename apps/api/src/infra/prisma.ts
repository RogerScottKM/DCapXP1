import { PrismaClient } from "@prisma/client";

declare global {
  // eslint-disable-next-line no-var
  var __dcapx_prisma: PrismaClient | undefined;
}

export const prisma =
  globalThis.__dcapx_prisma ??
  new PrismaClient({
    // log: ["error", "warn"], // optional
  });

if (process.env.NODE_ENV !== "production") {
  globalThis.__dcapx_prisma = prisma;
}
