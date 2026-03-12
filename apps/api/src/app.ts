// apps/api/src/app.ts
import express from "express";
import cors from "cors";
import { z } from "zod";
import type { Prisma } from "@prisma/client";
import { Decimal } from "@prisma/client/runtime/library";

import { requireAuth } from "./lib/auth";

// Step-1 infra singletons
import { enforceMandate } from "./middleware/ibac";
import { prisma } from "./infra/prisma";
import { bus } from "./infra/bus";
import { jsonReplacer } from "./infra/json";
import { symbolControl, isNewOrderAllowed, explainMode } from "./infra/symbolControl";
import { riskLimits } from "./infra/riskLimits";

// Modular routes
import agenticRoutes from "./routes/agentic";
import marketRoutes from "./routes/market";
import streamRoutes from "./routes/stream";
import adminRoutes from "./routes/admin";
import flagsRoutes from "./routes/flags";

import { resolveMode, type TradeMode } from "./infra/mode";

// Define Bus Event
type BusEvent = { type: "trade" | "orderbook"; symbol: string; mode: TradeMode };

/**  const m = raw.toUpperCase().trim(); */
/**  return m === "LIVE" ? "LIVE" : "PAPER"; */


export function makeApp() {

  const app = express();

  app.set("json replacer", jsonReplacer);
  app.use(cors({ origin: true }));
  app.use(express.json());

  /** util: resolve user from header (defaults to demo) */
  async function requireUser(req: express.Request) {
    const username = String(req.header("x-user") ?? "demo");
    const user = await prisma.user.findUnique({ where: { username } });
    if (!user) throw new Error(`unknown user '${username}'`);
    return user;
  }
  
  /** util: resolve trading mode from header/query/body (defaults to PAPER) */

    type TradeMode = "PAPER" | "LIVE";
    type BookKey = { symbol: string; mode: TradeMode };

    function normalizeKey(x: any): BookKey | null {
      if (typeof x === "string") return { symbol: x, mode: "PAPER" }; // legacy fallback
      if (x && typeof x.symbol === "string" && (x.mode === "PAPER" || x.mode === "LIVE")) return x;
      return null;
    }

/** added to help define req, res .... 24/02/2026 */
/** changed again ... >>> Agents to do the work! 05/03/2026 */

app.use(async (req, res, next) => {
  try {
    // Agent-signed requests handle identity elsewhere
    if (req.header("x-agent-id")) return next();

    // Public / anonymous requests must be allowed through
    const usernameHeader = req.header("x-user");
    if (!usernameHeader) return next();

    const user = await prisma.user.findUnique({
      where: { username: String(usernameHeader) },
    });

    if (user) {
      const mode = resolveMode(req);
      req.ctx = {
        user: { id: user.id, username: user.username },
        mode,
      };
    }

    return next();
  } catch (e) {
    console.error("[ctx middleware]", e);
    // IMPORTANT: never block public market-data routes here
    return next();
  }
});

  /** health */
  app.get("/health", (_req, res) => {
    res.json({ ok: true, ts: new Date().toISOString() });
  });

  // ====== ROUTE MOUNTS ======

  app.use("/api/v1/ui", agenticRoutes);
  app.use("/v1/ui", agenticRoutes);

  app.use("/api/v1/market", marketRoutes);

  app.use("/v1", streamRoutes);

  app.use("/api/v1/admin", adminRoutes);

  app.use("/api/v1/admin", flagsRoutes); // /api/v1/admin/flags/...

  // ====== CORE WRITE ENDPOINTS ======

  /** markets */
  app.get("/v1/markets", async (_req, res) => {
    const markets = await prisma.market.findMany({ orderBy: { symbol: "asc" } });
    res.json({ markets });
  });

  /** schema for placing an order */
  const orderSchema = z.object({
    symbol: z.string().min(1),
    side: z.enum(["BUY", "SELL"]),
    price: z.union([z.number(), z.string()]).transform((v) => v.toString()),
    qty: z.union([z.number(), z.string()]).transform((v) => v.toString()),
  });

  /** agents to do the work  ..... >> added 05/03/2026 */
  app.post("/v1/agent/orders", enforceMandate("TRADE"), async (req, res) => {
  try {
    const payload = orderSchema.parse(req.body);
    const mode = resolveMode(req);

    // ✅ IBAC middleware should have attached principal
    const principal = (req as any).principal;
    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ ok: false, error: "agent principal missing" });
    }

    // Resolve the owning user from principal.userId
    const user = await prisma.user.findUnique({ where: { id: principal.userId } });
    if (!user) return res.status(401).json({ ok: false, error: "unknown user for agent" });

    // Optional: attach ctx so your downstream code stays consistent
    req.ctx = { user: { id: user.id, username: user.username }, mode };

    // ---- From here down: same logic as your /v1/orders handler ----
    const symbol = payload.symbol.toUpperCase().trim();
    const events: BusEvent[] = [];

    const control = symbolControl.get(symbol);
    if (!isNewOrderAllowed(control.mode)) {
      return res.status(423).json({
        ok: false,
        symbol,
        mode: control.mode,
        control,
        error: explainMode(control.mode),
      });
    }

    const priceD = new Decimal(payload.price);
    const qtyD = new Decimal(payload.qty);
    if (priceD.lte(0) || qtyD.lte(0)) {
      return res.status(400).json({ ok: false, error: "price and qty must be > 0" });
    }

    const limits = riskLimits.get(symbol);

    if (limits.maxOrderQty) {
      const maxQ = new Decimal(limits.maxOrderQty);
      if (qtyD.gt(maxQ)) {
        return res.status(429).json({
          ok: false,
          symbol,
          code: "MAX_ORDER_QTY",
          error: `Order qty exceeds maxOrderQty (${maxQ.toString()})`,
          limits,
        });
      }
    }

    if (limits.maxOrderNotional) {
      const maxN = new Decimal(limits.maxOrderNotional);
      const notional = priceD.mul(qtyD);
      if (notional.gt(maxN)) {
        return res.status(429).json({
          ok: false,
          symbol,
          code: "MAX_ORDER_NOTIONAL",
          error: `Order notional exceeds maxOrderNotional (${maxN.toString()})`,
          limits,
          notional: notional.toString(),
        });
      }
    }

    if (typeof limits.maxOpenOrders === "number") {
      const openCount = await prisma.order.count({
        where: { userId: user.id, symbol, status: "OPEN", mode },
      });

      if (openCount >= limits.maxOpenOrders) {
        return res.status(429).json({
          ok: false,
          symbol,
          code: "MAX_OPEN_ORDERS",
          error: `Open orders limit reached (${limits.maxOpenOrders})`,
          limits,
          openCount,
        });
      }
    }

    const result = await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
      const incoming = await tx.order.create({
        data: {
          mode,
          userId: user.id,
          symbol,
          side: payload.side,
          price: new Decimal(payload.price),
          qty: new Decimal(payload.qty),
          status: "OPEN",
        },
      });

      await match(tx, incoming, events);
      return await tx.order.findUnique({ where: { id: incoming.id } });
    });

    for (const e of events) bus.emit(e.type, { symbol: e.symbol, mode: e.mode });

    return res.json({ ok: true, order: result });
  } catch (err: any) {
    return res.status(400).json({ ok: false, error: String(err?.message ?? err) });
  }
});

  /** place order (and match) */
  app.post("/v1/orders", requireAuth, async (req, res) => {
    try {
      console.log("[/v1/orders] body =", req.body);
      const payload = orderSchema.parse(req.body);
      const mode = resolveMode(req); // ✅ ADD THIS

      const userId = req.userId;
if (!userId) return res.status(401).json({ ok: false, error: "unauthorized" });

const user = await prisma.user.findUnique({ where: { id: userId } });
if (!user) return res.status(401).json({ ok: false, error: "unknown user" });                                          
 
      const symbol = payload.symbol.toUpperCase().trim();

      const events: BusEvent[] = []; 

      // 1) Kill-switch (per symbol)
      const control = symbolControl.get(symbol);
      if (!isNewOrderAllowed(control.mode)) {
        return res.status(423).json({
          ok: false,
          symbol,
          mode: control.mode,
          control,
          error: explainMode(control.mode),
        });
      }

      // 2) Basic numeric sanity
      const priceD = new Decimal(payload.price);
      const qtyD = new Decimal(payload.qty);
      if (priceD.lte(0) || qtyD.lte(0)) {
        return res.status(400).json({ ok: false, error: "price and qty must be > 0" });
      }

      // 3) Risk limits (per symbol)
      const limits = riskLimits.get(symbol);

      if (limits.maxOrderQty) {
        const maxQ = new Decimal(limits.maxOrderQty);
        if (qtyD.gt(maxQ)) {
          return res.status(429).json({
            ok: false,
            symbol,
            code: "MAX_ORDER_QTY",
            error: `Order qty exceeds maxOrderQty (${maxQ.toString()})`,
            limits,
          });
        }
      }

      if (limits.maxOrderNotional) {
        const maxN = new Decimal(limits.maxOrderNotional);
        const notional = priceD.mul(qtyD);
        if (notional.gt(maxN)) {
          return res.status(429).json({
            ok: false,
            symbol,
            code: "MAX_ORDER_NOTIONAL",
            error: `Order notional exceeds maxOrderNotional (${maxN.toString()})`,
            limits,
            notional: notional.toString(),
          });
        }
      }

      if (typeof limits.maxOpenOrders === "number") {
        const openCount = await prisma.order.count({
          where: { userId: user.id, symbol, status: "OPEN", mode },  // ✅ add mode
        });

        if (openCount >= limits.maxOpenOrders) {
          return res.status(429).json({
            ok: false,
            symbol,
            code: "MAX_OPEN_ORDERS",
            error: `Open orders limit reached (${limits.maxOpenOrders})`,
            limits,
            openCount,
          });
        }
      }

      const result = await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
        const incoming = await tx.order.create({
          data: {
            mode,               // ✅ ADD THIS LINE
            userId: user.id,
            symbol,
            side: payload.side,
            price: new Decimal(payload.price),
            qty: new Decimal(payload.qty),
            status: "OPEN",
          },
        });

        await match(tx, incoming, events);

        return await tx.order.findUnique({ where: { id: incoming.id } });
      });

                  // ✅ emit only after commit
    for (const e of events) bus.emit(e.type, { symbol: e.symbol, mode: e.mode });

    res.json({ ok: true, order: result });
  } catch (err: any) {
    res.status(400).json({ ok: false, error: String(err?.message ?? err) });
  }
});

       /** cancel (scoped by user+mode) */
app.post("/v1/orders/:id/cancel", requireAuth, async (req, res) => {
  const idStr = req.params.id;
  if (!/^\d+$/.test(idStr)) return res.status(400).json({ ok: false, error: "bad id" });

  const id = BigInt(idStr);

  const ctx = req.ctx;
  if (!ctx) return res.status(401).json({ ok: false, error: "unauthorized" });

  const userId = ctx.user.id;   // ✅ string ((User.id is String/cuid))
  const mode = ctx.mode;        // ✅ "PAPER" | "LIVE"

  const result = await prisma.order.updateMany({
    where: { id, userId, mode, status: "OPEN" },
    data: { status: "CANCELLED" },
  });

  if (result.count === 0) {
    const ord = await prisma.order.findFirst({
      where: { id, userId, mode },
      select: { status: true },
    });

    if (!ord) return res.status(404).json({ ok: false, error: "not found" });
    return res.status(400).json({ ok: false, error: "not open" });
  }

  const ord = await prisma.order.findFirst({
    where: { id, userId, mode },
    select: { symbol: true, mode: true },
  });

  if (ord) bus.emit("orderbook", { symbol: ord.symbol, mode: ord.mode });
  return res.json({ ok: true });
});

  /** ME + Balances */
  app.get("/v1/me", requireAuth, async (req, res) => {
    try {
      const userId = req.userId;
if (!userId) return res.status(401).json({ ok: false, error: "unauthorized" });

const user = await prisma.user.findUnique({ where: { id: userId } });
if (!user) return res.status(401).json({ ok: false, error: "unknown user" });
      const mode = resolveMode(req);

      const full = await prisma.user.findUnique({
        where: { id: user.id },
        include: {
          kyc: true,
          balances: { where: { mode } }, // ✅ filter by mode
        },
      });

      res.json({ ok: true, mode, user: full });
    } catch (e: any) {
      res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
  });

  app.get("/v1/balances", requireAuth, async (req, res) => {
    try {
      const userId = req.userId;
if (!userId) return res.status(401).json({ ok: false, error: "unauthorized" });

const user = await prisma.user.findUnique({ where: { id: userId } });
if (!user) return res.status(401).json({ ok: false, error: "unknown user" });
      const mode = resolveMode(req);

      const balances = await prisma.balance.findMany({
        where: { userId: user.id, mode }, // ✅ filter by mode
      });

      res.json({ ok: true, mode, balances });
    } catch (e: any) {
      res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
  });

    /** My Orders / Trades */
app.get("/v1/my/orders", requireAuth, async (req, res) => {
  try {
    const userId = req.userId;
if (!userId) return res.status(401).json({ ok: false, error: "unauthorized" });

const user = await prisma.user.findUnique({ where: { id: userId } });
if (!user) return res.status(401).json({ ok: false, error: "unknown user" });
    const mode = resolveMode(req); // ✅ add this

    const status = (req.query.status as string | undefined) as any;

    const where: any = { userId: user.id, mode }; // ✅ include mode
    if (status) where.status = status;

    const orders = await prisma.order.findMany({
      where,
      orderBy: { createdAt: "desc" },
      take: 200,
    });

    res.json({ ok: true, mode, orders });
  } catch (e: any) {
    res.status(400).json({ ok: false, error: String(e?.message ?? e) });
  }
});

  app.get("/v1/my/trades", requireAuth, async (req, res) => {
   try {
    const userId = req.userId;
if (!userId) return res.status(401).json({ ok: false, error: "unauthorized" });

const user = await prisma.user.findUnique({ where: { id: userId } });
if (!user) return res.status(401).json({ ok: false, error: "unknown user" });
    const mode = resolveMode(req); // ✅ add this

    const trades = await prisma.trade.findMany({
      where: {
        mode, // ✅ include mode
        OR: [
          { buyOrder: { userId: user.id, mode } },  // ✅ mode-safe
          { sellOrder: { userId: user.id, mode } }, // ✅ mode-safe
        ],
      },
      orderBy: { createdAt: "desc" },
      take: 200,
      include: {
        buyOrder: { select: { id: true, symbol: true, userId: true, mode: true } },  // optional but helpful
        sellOrder: { select: { id: true, symbol: true, userId: true, mode: true } }, // optional but helpful
      },
    });

    res.json({ ok: true, mode, trades });
  } catch (e: any) {
    res.status(400).json({ ok: false, error: String(e?.message ?? e) });
  }
});

    /** Faucet (demo funding) */
  app.post("/v1/faucet", requireAuth, async (req, res) => {
    try {
      const userId = req.userId;
if (!userId) return res.status(401).json({ ok: false, error: "unauthorized" });

const user = await prisma.user.findUnique({ where: { id: userId } });
if (!user) return res.status(401).json({ ok: false, error: "unknown user" });

      // ✅ resolve mode (PAPER by default)
      const mode = resolveMode(req);

      // OPTIONAL: enforce faucet is PAPER-only (recommended for compliance)
      // if (mode === "LIVE") {
      //   return res.status(403).json({ ok: false, error: "Faucet is PAPER-only" });
      // }

      const { asset, amount } = req.body ?? {};
      if (!asset || !amount) {
        return res.status(400).json({ ok: false, error: "asset & amount required" });
      }

      const assetCode = String(asset).toUpperCase().trim();
      const amt = new Decimal(String(amount));

      await prisma.balance.upsert({
        where: { userId_mode_asset: { userId: user.id, mode, asset: assetCode } },
        update: { amount: { increment: amt } },
        create: { userId: user.id, mode, asset: assetCode, amount: amt },
      });

      res.json({ ok: true, mode });
    } catch (e: any) {
      res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
  });

  /** KYC submit (demo) */
  app.post("/v1/kyc/submit", requireAuth, async (req, res) => {
    try {
      const user = await requireUser(req);
      const { legalName, country, dob, docType, docHash } = req.body ?? {};
      if (!legalName || !country || !dob || !docType || !docHash) {
        return res.status(400).json({ ok: false, error: "missing fields" });
      }

      const rec = await prisma.kyc.upsert({
        where: { userId: user.id },
        update: {
          legalName,
          country,
          dob: new Date(dob),
          docType,
          docHash,
          status: "PENDING",
          updatedAt: new Date(),
        },
        create: {
          userId: user.id,
          legalName,
          country,
          dob: new Date(dob),
          docType,
          docHash,
          status: "PENDING",
          riskScore: new Decimal(0),
        },
      });

      res.json({ ok: true, kyc: rec });
    } catch (e: any) {
      res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
  });

  return app;
}

/** price-time-priority matching */
 
async function match(tx: Prisma.TransactionClient, order: any, events: BusEvent[]) {
  let remaining = new Decimal(order.qty);
  const limit = new Decimal(order.price);
  const isBuy = order.side === "BUY";

  while (remaining.gt(0)) {
    const counter = await tx.order.findFirst({
      where: {
        symbol: order.symbol,
        mode: order.mode,
        status: "OPEN",
        side: isBuy ? "SELL" : "BUY",
        price: isBuy ? { lte: limit } : { gte: limit },
      },
      orderBy: [{ price: isBuy ? "asc" : "desc" }, { createdAt: "asc" }],
    });

    if (!counter) break;

    const tradeQty = Decimal.min(remaining, counter.qty);
    const tradePrice = counter.price;

    await tx.trade.create({
      data: {
        mode: order.mode,
        symbol: order.symbol,
        price: tradePrice,
        qty: tradeQty,
        buyOrderId: isBuy ? order.id : counter.id,
        sellOrderId: isBuy ? counter.id : order.id,
      },
    });

    // ✅ record events (emit after commit)
    events.push({ type: "trade", symbol: order.symbol, mode: order.mode });
    events.push({ type: "orderbook", symbol: order.symbol, mode: order.mode });

    const counterLeft = counter.qty.minus(tradeQty);
    await tx.order.update({
      where: { id: counter.id },
      data: counterLeft.lte(0)
        ? { status: "FILLED", qty: new Decimal(0) }
        : { qty: counterLeft },
    });

    remaining = remaining.minus(tradeQty);
  }

  await tx.order.update({
    where: { id: order.id },
    data: remaining.lte(0)
      ? { status: "FILLED", qty: new Decimal(0) }
      : { qty: remaining },
  });
}
export const createApp = makeApp;
