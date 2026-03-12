/*
  Warnings:

  - A unique constraint covering the columns `[userId,mode,asset]` on the table `Balance` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "TradeMode" AS ENUM ('PAPER', 'LIVE');

-- DropIndex
DROP INDEX "Balance_userId_asset_key";

-- DropIndex
DROP INDEX "Order_symbol_side_status_price_createdAt_idx";

-- DropIndex
DROP INDEX "Trade_symbol_createdAt_idx";

-- AlterTable
ALTER TABLE "Asset" ADD COLUMN     "issuerControlled" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "Balance" ADD COLUMN     "mode" "TradeMode" NOT NULL DEFAULT 'PAPER';

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "mode" "TradeMode" NOT NULL DEFAULT 'PAPER';

-- AlterTable
ALTER TABLE "Trade" ADD COLUMN     "mode" "TradeMode" NOT NULL DEFAULT 'PAPER';

-- CreateIndex
CREATE INDEX "Balance_userId_mode_idx" ON "Balance"("userId", "mode");

-- CreateIndex
CREATE UNIQUE INDEX "Balance_userId_mode_asset_key" ON "Balance"("userId", "mode", "asset");

-- CreateIndex
CREATE INDEX "Order_symbol_mode_side_status_price_createdAt_idx" ON "Order"("symbol", "mode", "side", "status", "price", "createdAt");

-- CreateIndex
CREATE INDEX "Trade_symbol_mode_createdAt_idx" ON "Trade"("symbol", "mode", "createdAt");
