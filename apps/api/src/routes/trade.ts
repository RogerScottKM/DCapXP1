import { Router } from "express";
import { z } from "zod";
import { enforceMandate, bumpOrdersPlaced } from "../middleware/ibac";

const router = Router();

const orderSchema = z.object({
  symbol: z.string().min(3).max(40), // "BTC-USD"
  side: z.enum(["BUY", "SELL"]),
  type: z.enum(["LIMIT", "MARKET"]),
  qty: z.string(), // keep as string; convert using your quantums rules
  price: z.string().optional(), // required for LIMIT
  tif: z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional(),
});

router.post("/orders", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const payload = orderSchema.parse(req.body);

    const principal = req.principal;
    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    // ===== Hook into your engine here =====
    // const order = await engine.processOrder(principal.userId, payload, { agentId: principal.agentId });
    const order = {
      id: "demo_order",
      userId: principal.userId,
      agentId: principal.agentId,
      symbol: payload.symbol,
      side: payload.side,
      type: payload.type,
      qty: payload.qty,
      price: payload.price ?? null,
      status: "ACCEPTED",
    };

    // Count only accepted orders
    await bumpOrdersPlaced(principal.mandateId);

    return res.json({ ok: true, order });
  } catch (e: any) {
    return res.status(400).json({ ok: false, error: e?.message ?? "Bad request" });
  }
});

export default router;
