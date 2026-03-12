/*
  Warnings:

  - You are about to drop the column `base` on the `Market` table. All the data in the column will be lost.
  - You are about to drop the column `quote` on the `Market` table. All the data in the column will be lost.
  - The primary key for the `Order` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - You are about to drop the column `userId` on the `Order` table. All the data in the column will be lost.
  - The `id` column on the `Order` table would be dropped and recreated. This will lead to data loss if there is data in the column.
  - The primary key for the `Trade` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The `id` column on the `Trade` table would be dropped and recreated. This will lead to data loss if there is data in the column.
  - The `buyOrderId` column on the `Trade` table would be dropped and recreated. This will lead to data loss if there is data in the column.
  - The `sellOrderId` column on the `Trade` table would be dropped and recreated. This will lead to data loss if there is data in the column.
  - You are about to drop the `ApiKey` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `Balance` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `User` table. If the table is not empty, all the data it contains will be lost.
  - Added the required column `baseAsset` to the `Market` table without a default value. This is not possible if the table is not empty.
  - Added the required column `lotSize` to the `Market` table without a default value. This is not possible if the table is not empty.
  - Added the required column `quoteAsset` to the `Market` table without a default value. This is not possible if the table is not empty.
  - Added the required column `tickSize` to the `Market` table without a default value. This is not possible if the table is not empty.

*/
-- AlterEnum
ALTER TYPE "OrderStatus" ADD VALUE 'PARTIAL';

-- DropForeignKey
ALTER TABLE "ApiKey" DROP CONSTRAINT "ApiKey_userId_fkey";

-- DropForeignKey
ALTER TABLE "Balance" DROP CONSTRAINT "Balance_userId_fkey";

-- DropForeignKey
ALTER TABLE "Order" DROP CONSTRAINT "Order_userId_fkey";

-- AlterTable
ALTER TABLE "Market" DROP COLUMN "base",
DROP COLUMN "quote",
ADD COLUMN     "baseAsset" TEXT NOT NULL,
ADD COLUMN     "lotSize" DECIMAL(18,8) NOT NULL,
ADD COLUMN     "quoteAsset" TEXT NOT NULL,
ADD COLUMN     "tickSize" DECIMAL(18,8) NOT NULL;

-- AlterTable
ALTER TABLE "Order" DROP CONSTRAINT "Order_pkey",
DROP COLUMN "userId",
ADD COLUMN     "filled" DECIMAL(38,18) NOT NULL DEFAULT 0,
DROP COLUMN "id",
ADD COLUMN     "id" BIGSERIAL NOT NULL,
ADD CONSTRAINT "Order_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "Trade" DROP CONSTRAINT "Trade_pkey",
DROP COLUMN "id",
ADD COLUMN     "id" BIGSERIAL NOT NULL,
DROP COLUMN "buyOrderId",
ADD COLUMN     "buyOrderId" BIGINT,
DROP COLUMN "sellOrderId",
ADD COLUMN     "sellOrderId" BIGINT,
ADD CONSTRAINT "Trade_pkey" PRIMARY KEY ("id");

-- DropTable
DROP TABLE "ApiKey";

-- DropTable
DROP TABLE "Balance";

-- DropTable
DROP TABLE "User";

-- CreateIndex
CREATE INDEX "Order_symbol_side_status_price_createdAt_idx" ON "Order"("symbol", "side", "status", "price", "createdAt");

-- CreateIndex
CREATE INDEX "Trade_symbol_createdAt_idx" ON "Trade"("symbol", "createdAt");

-- AddForeignKey
ALTER TABLE "Trade" ADD CONSTRAINT "Trade_buyOrderId_fkey" FOREIGN KEY ("buyOrderId") REFERENCES "Order"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Trade" ADD CONSTRAINT "Trade_sellOrderId_fkey" FOREIGN KEY ("sellOrderId") REFERENCES "Order"("id") ON DELETE SET NULL ON UPDATE CASCADE;
