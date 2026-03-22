"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const ibac_1 = require("../middleware/ibac");
const router = (0, express_1.Router)();
const orderSchema = zod_1.z.object({
    symbol: zod_1.z.string().min(3).max(40), // "BTC-USD"
    side: zod_1.z.enum(["BUY", "SELL"]),
    type: zod_1.z.enum(["LIMIT", "MARKET"]),
    qty: zod_1.z.string(), // keep as string; convert using your quantums rules
    price: zod_1.z.string().optional(), // required for LIMIT
    tif: zod_1.z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional(),
});
router.post("/orders", (0, ibac_1.enforceMandate)("TRADE"), async (req, res) => {
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
        await (0, ibac_1.bumpOrdersPlaced)(principal.mandateId);
        return res.json({ ok: true, order });
    }
    catch (e) {
        return res.status(400).json({ ok: false, error: e?.message ?? "Bad request" });
    }
});
exports.default = router;
