// apps/api/src/services/marketData.ts
import { prisma } from "../infra/prisma";
import { aggregateByPrice } from "../lib/marketCommon";

export async function getRecentTrades(symbol: string, take = 50) {
  return prisma.trade.findMany({
    where: { symbol },
    orderBy: { createdAt: "desc" },
    take,
  });
}

export async function getOrderbookL3(symbol: string, depth: number) {
  const [bids, asks] = await Promise.all([
    prisma.order.findMany({
      where: { symbol, side: "BUY", status: "OPEN" },
      orderBy: [{ price: "desc" }, { createdAt: "asc" }],
      take: depth,
    }),
    prisma.order.findMany({
      where: { symbol, side: "SELL", status: "OPEN" },
      orderBy: [{ price: "asc" }, { createdAt: "asc" }],
      take: depth,
    }),
  ]);

  return { bids, asks };
}

export async function getOrderbookL2(symbol: string, depth: number) {
  // For aggregation we need to fetch more than depth (duplicates collapse).
  const takeRaw = Math.min(Math.max(depth * 50, 200), 2000);

  const [bidOrders, askOrders] = await Promise.all([
    prisma.order.findMany({
      where: { symbol, side: "BUY", status: "OPEN" },
      orderBy: [{ price: "desc" }, { createdAt: "asc" }],
      take: takeRaw,
    }),
    prisma.order.findMany({
      where: { symbol, side: "SELL", status: "OPEN" },
      orderBy: [{ price: "asc" }, { createdAt: "asc" }],
      take: takeRaw,
    }),
  ]);

  return {
    bids: aggregateByPrice(bidOrders, depth),
    asks: aggregateByPrice(askOrders, depth),
  };
}
