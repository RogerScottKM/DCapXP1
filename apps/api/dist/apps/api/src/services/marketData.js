"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getRecentTrades = getRecentTrades;
exports.getOrderbookL3 = getOrderbookL3;
exports.getOrderbookL2 = getOrderbookL2;
// apps/api/src/services/marketData.ts
const prisma_1 = require("../infra/prisma");
const marketCommon_1 = require("../lib/marketCommon");
async function getRecentTrades(symbol, take = 50) {
    return prisma_1.prisma.trade.findMany({
        where: { symbol },
        orderBy: { createdAt: "desc" },
        take,
    });
}
async function getOrderbookL3(symbol, depth) {
    const [bids, asks] = await Promise.all([
        prisma_1.prisma.order.findMany({
            where: { symbol, side: "BUY", status: "OPEN" },
            orderBy: [{ price: "desc" }, { createdAt: "asc" }],
            take: depth,
        }),
        prisma_1.prisma.order.findMany({
            where: { symbol, side: "SELL", status: "OPEN" },
            orderBy: [{ price: "asc" }, { createdAt: "asc" }],
            take: depth,
        }),
    ]);
    return { bids, asks };
}
async function getOrderbookL2(symbol, depth) {
    // For aggregation we need to fetch more than depth (duplicates collapse).
    const takeRaw = Math.min(Math.max(depth * 50, 200), 2000);
    const [bidOrders, askOrders] = await Promise.all([
        prisma_1.prisma.order.findMany({
            where: { symbol, side: "BUY", status: "OPEN" },
            orderBy: [{ price: "desc" }, { createdAt: "asc" }],
            take: takeRaw,
        }),
        prisma_1.prisma.order.findMany({
            where: { symbol, side: "SELL", status: "OPEN" },
            orderBy: [{ price: "asc" }, { createdAt: "asc" }],
            take: takeRaw,
        }),
    ]);
    return {
        bids: (0, marketCommon_1.aggregateByPrice)(bidOrders, depth),
        asks: (0, marketCommon_1.aggregateByPrice)(askOrders, depth),
    };
}
