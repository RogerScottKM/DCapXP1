// apps/api/src/routes/market.ts
import express from "express";
import { prisma } from "../infra/prisma";
import { featureFlags } from "../infra/featureFlags";
import { isAdmin } from "../infra/adminKey";
import { requireAuth } from "../lib/auth";
import {
  aggregateByPrice,
  parseBookLevel,
  parsePositiveInt,
  type BookLevel,
} from "./marketShared";

import { TradeMode } from "@prisma/client";

const parseTradeMode = (v?: string): TradeMode | undefined => {
  if (!v) return undefined;
  const u = v.toUpperCase();
  if (u === "PAPER") return TradeMode.PAPER;
  if (u === "LIVE") return TradeMode.LIVE;
  return undefined;
};

// near the top of apps/api/src/routes/market.ts (after imports)
const q1 = (v: unknown): string | undefined =>
  typeof v === "string" ? v : Array.isArray(v) ? v[0] : undefined;

const router = express.Router();

/**
 * GET /api/v1/market/orderbook?symbol=BTC-USD&depth=20&level=2|3
 * - level defaults to flags.orderbookDefaultLevel (usually 2)
 * - L3 is gated unless admin or flags.publicAllowL3=true
 */
router.get("/orderbook", async (req, res) => {
  try {
    const symbol = String(req.query.symbol ?? "").toUpperCase().trim();
    if (!symbol) {
      return res.status(400).json({ ok: false, error: "symbol required" });
    }

    const depth = parsePositiveInt(req.query.depth, 20, { min: 1, max: 500 });

    const flags = featureFlags.get(symbol);

    // default level if not provided
    const requested = req.query.level;
    const level: BookLevel =
      requested === undefined || requested === null || String(requested).trim() === ""
        ? flags.orderbookDefaultLevel
        : parseBookLevel(requested, flags.orderbookDefaultLevel);

    // L3 gating
    if (level === 3 && !isAdmin(req) && !flags.publicAllowL3) {
      return res.status(403).json({
        ok: false,
        symbol,
        code: "L3_DISABLED",
        error:
          "L3 orderbook is disabled for public requests. Provide x-admin-key or enable publicAllowL3.",
        flags: {
          publicAllowL3: flags.publicAllowL3,
          orderbookDefaultLevel: flags.orderbookDefaultLevel,
        },
      });
    }

    // For L2 aggregation we need to fetch more than depth (duplicates collapse).
    const takeRaw = Math.min(Math.max(depth * 50, 200), 2000);

    const [bidOrders, askOrders] = await Promise.all([
      prisma.order.findMany({
        where: { symbol, side: "BUY", status: "OPEN" },
        orderBy: [{ price: "desc" }, { createdAt: "asc" }],
        take: level === 3 ? depth : takeRaw,
      }),
      prisma.order.findMany({
        where: { symbol, side: "SELL", status: "OPEN" },
        orderBy: [{ price: "asc" }, { createdAt: "asc" }],
        take: level === 3 ? depth : takeRaw,
      }),
    ]);

    if (level === 3) {
      return res.json({
        ok: true,
        symbol,
        depth,
        level: 3 as const,
        bids: bidOrders,
        asks: askOrders,
        flags: {
          publicAllowL3: flags.publicAllowL3,
          orderbookDefaultLevel: flags.orderbookDefaultLevel,
        },
      });
    }

    return res.json({
      ok: true,
      symbol,
      depth,
      level: 2 as const,
      bids: aggregateByPrice(bidOrders, depth),
      asks: aggregateByPrice(askOrders, depth),
      flags: {
        publicAllowL3: flags.publicAllowL3,
        orderbookDefaultLevel: flags.orderbookDefaultLevel,
      },
    });
  } catch (e: any) {
    console.error(e);
    return res.status(500).json({ ok: false, error: String(e?.message ?? e) });
  }
});

/**
 * GET /api/v1/market/trades?symbol=?
 */
router.get("/trades", async (req, res) => {
  try {
    const symbol = String(req.query.symbol ?? "").toUpperCase().trim();
    if (!symbol) {
      return res.status(400).json({ ok: false, error: "symbol required" });
    }

    const limitRaw = q1(req.query.limit);
    const limit = Math.min(Math.max(Number(limitRaw ?? "50"), 1), 20000);

    const mode = parseTradeMode(q1(req.query.mode));

    const sinceRaw =
      q1(req.query.sinceMs) ??
      q1(req.query.fromMs) ??
      q1(req.query.afterMs);

    const where: any = { symbol };

    if (mode) {
      where.mode = mode;
    }

    if (sinceRaw) {
      const sinceMs = Number(sinceRaw);
      if (Number.isFinite(sinceMs) && sinceMs > 0) {
        where.createdAt = { gte: new Date(sinceMs) };
      }
    }

    const trades = await prisma.trade.findMany({
      where,
      orderBy: { createdAt: "desc" },
      take: limit,
      select: {
        id: true,
        symbol: true,
        price: true,
        qty: true,
        createdAt: true,
        mode: true,
        buyOrderId: true,
        sellOrderId: true,
      },
    });

    return res.json({
      ok: true,
      symbol,
      mode: mode ?? null,
      limit,
      trades,
    });
  } catch (e: any) {
    console.error("[market/trades]", e);
    return res.status(500).json({ ok: false, error: String(e?.message ?? e) });
  }
});


/**
 * GET /api/v1/market/candles?symbol=?&period=24h
 * Demo candles: stable synthetic candles based on latest trade (or 100 fallback).
 */
router.get("/candles", async (req, res) => {
  try {
    const symbol = String(req.query.symbol ?? "").toUpperCase().trim();
    if (!symbol) return res.status(400).json({ ok: false, error: "symbol required" });

    const period = String(req.query.period ?? "24h").trim();

    const durationMs =
      period === "1h" ? 60 * 60 * 1000 :
      period === "4h" ? 4 * 60 * 60 * 1000 :
      period === "24h" ? 24 * 60 * 60 * 1000 :
      period === "7d" ? 7 * 24 * 60 * 60 * 1000 :
      period === "30d" ? 30 * 24 * 60 * 60 * 1000 :
      24 * 60 * 60 * 1000;

    const intervalMs =
      durationMs <= 24 * 60 * 60 * 1000 ? 5 * 60 * 1000 :
      durationMs <= 7 * 24 * 60 * 60 * 1000 ? 60 * 60 * 1000 :
      4 * 60 * 60 * 1000;

    const now = Date.now();
    const start = now - durationMs;
    const alignedStart = start - (start % intervalMs);

    // get trades in-range (oldest -> newest)
    const trades = await prisma.trade.findMany({
      where: {
        symbol,
        createdAt: {
          gte: new Date(alignedStart),
          lte: new Date(now),
        },
      },
      orderBy: { createdAt: "asc" },
      select: { createdAt: true, price: true, qty: true },
    });

    // fallback price if no trades in range
    const latest = await prisma.trade.findFirst({
      where: { symbol },
      orderBy: { createdAt: "desc" },
      select: { price: true },
    });
    const fallbackPx = Number(latest?.price?.toString?.() ?? "100");

    const byBucket = new Map<number, { t: number; o: number; h: number; l: number; c: number; v: number }>();

    for (const tr of trades) {
      const ts = new Date(tr.createdAt).getTime();
      const b = ts - (ts % intervalMs); // bucket start
      const p = Number(tr.price);
      const q = Number(tr.qty);

      const cur = byBucket.get(b);
      if (!cur) {
        byBucket.set(b, { t: b, o: p, h: p, l: p, c: p, v: q });
      } else {
        cur.h = Math.max(cur.h, p);
        cur.l = Math.min(cur.l, p);
        cur.c = p;
        cur.v += q;
      }
    }

    const candles: Array<{ t: number; o: number; h: number; l: number; c: number; v: number }> = [];

    let prevClose = fallbackPx;
    for (let t = alignedStart; t <= now; t += intervalMs) {
      const c = byBucket.get(t);
      if (c) {
        candles.push(c);
        prevClose = c.c;
      } else {
        // gap candle: flat at previous close
        candles.push({ t, o: prevClose, h: prevClose, l: prevClose, c: prevClose, v: 0 });
      }
    }

    return res.json({ ok: true, symbol, period, intervalMs, candles });

  } catch (e: any) {
    console.error(e);
    return res.status(500).json({ ok: false, error: String(e?.message ?? e) });
  }
});

// --- DEMO: open orders feed for UI panel ---

// apps/api/src/routes/market.ts

router.get("/open-orders", async (req, res) => {
  try {
    const limit = Math.min(Number(req.query.limit ?? 50), 500);

    const userId = q1(req.query.userId);   // ✅ cuid string
    const symbol = q1(req.query.symbol);
    const mode = parseTradeMode(q1(req.query.mode));

    const where: any = { status: "OPEN" };
    if (symbol) where.symbol = symbol;
    if (mode) where.mode = mode;
    if (userId) where.userId = userId;

    const rows = await prisma.order.findMany({
      where,
      orderBy: { createdAt: "desc" },
      take: limit,
      select: {
        id: true,        // BigInt
        symbol: true,
        side: true,
        price: true,     // Decimal
        qty: true,       // Decimal
        status: true,
        createdAt: true,
        userId: true,
        mode: true,
      },
    });

    // ✅ JSON-safe mapping (BigInt -> string, Decimal -> string)
    const orders = rows.map((o) => ({
      ...o,
      id: o.id.toString(),
      price: o.price.toString(),
      qty: o.qty.toString(),
    }));

    res.json({
      ok: true,
      symbol: symbol ?? null,
      userId: userId ?? null,
      mode: mode ?? null,
      limit,
      orders,
    });
  } catch (e) {
    console.error("[open-orders]", e);
    res.status(500).json({ ok: false, error: "OpenOrdersFailed" });
  }
});

// --- DEMO: positions (spot balances) feed for UI panel ---

router.get("/positions", async (req, res) => {
  try {
    const userId =
      q1(req.query.userId) ??
      req.userId ??
      req.ctx?.user?.id ??
      undefined;

    const mode = parseTradeMode(q1(req.query.mode)) ?? TradeMode.PAPER;

    // anonymous request -> no private balances, but not an error
    if (!userId) {
      return res.json({
        ok: true,
        userId: null,
        mode,
        balances: [],
      });
    }

    const rows = await prisma.balance.findMany({
      where: { userId, mode },
      orderBy: { asset: "asc" },
      select: {
        asset: true,
        amount: true,
        mode: true,
      },
    });

    const balances = rows.map((b) => ({
      asset: b.asset,
      amount: b.amount.toString(),
      mode: b.mode,
    }));

    return res.json({
      ok: true,
      userId,
      mode,
      balances,
    });
  } catch (e: any) {
    console.error("[positions]", e);
    return res.status(500).json({ ok: false, error: String(e?.message ?? e) });
  }
});

export default router;
