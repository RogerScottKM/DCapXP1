import { Prisma, PrismaClient } from "@prisma/client";

export type Tx = Prisma.TransactionClient;

export async function withTx<T>(
  prisma: PrismaClient,
  fn: (tx: Tx) => Promise<T>,
): Promise<T> {
  return prisma.$transaction((tx) => fn(tx));
}
