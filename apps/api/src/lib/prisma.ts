import { PrismaClient } from "@prisma/client";

type GlobalPrisma = typeof globalThis & {
  __dcapxPrisma?: PrismaClient;
};

const globalForPrisma = globalThis as GlobalPrisma;

export const prisma = globalForPrisma.__dcapxPrisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.__dcapxPrisma = prisma;
}

export default prisma;
