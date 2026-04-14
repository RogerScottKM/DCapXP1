-- Add PARTIALLY_FILLED and CANCEL_PENDING to OrderStatus enum.
-- These are safe ALTER TYPE ... ADD VALUE statements (Postgres 9.1+).
-- They cannot run inside a multi-statement transaction, so Prisma
-- must apply them one at a time.

ALTER TYPE "OrderStatus" ADD VALUE IF NOT EXISTS 'PARTIALLY_FILLED';
ALTER TYPE "OrderStatus" ADD VALUE IF NOT EXISTS 'CANCEL_PENDING';
