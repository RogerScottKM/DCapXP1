-- Phase 3C: add TimeInForce enum and Order.timeInForce column.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'TimeInForce') THEN
    CREATE TYPE "TimeInForce" AS ENUM ('GTC', 'IOC', 'FOK', 'POST_ONLY');
  END IF;
END $$;

ALTER TABLE "Order"
  ADD COLUMN IF NOT EXISTS "timeInForce" "TimeInForce" NOT NULL DEFAULT 'GTC';
