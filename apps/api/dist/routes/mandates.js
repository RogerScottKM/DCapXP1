"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const prisma_1 = require("../prisma");
const auth_1 = require("../middleware/auth");
const quantums_1 = require("../utils/quantums");
const router = (0, express_1.Router)();
const issueMandateSchema = zod_1.z.object({
    action: zod_1.z.enum(["TRADE", "WITHDRAW", "TRANSFER"]),
    market: zod_1.z.string().min(3).max(40).optional(), // e.g. BTC-USD
    maxNotionalPerDay: zod_1.z.string().optional(), // e.g. "1000.50"
    quoteDecimals: zod_1.z.number().int().min(0).max(18).optional(), // default 6
    maxOrdersPerDay: zod_1.z.number().int().min(0).max(1_000_000).optional(),
    notBefore: zod_1.z.string().datetime().optional(),
    expiresAt: zod_1.z.string().datetime(),
    constraints: zod_1.z.any().optional(),
    mandateJwtHash: zod_1.z.string().optional(),
});
// Issue mandate to an agent you own
router.post("/agents/:agentId", auth_1.requireUser, auth_1.requireMfa, async (req, res) => {
    const agentId = String(req.params.agentId);
    const body = issueMandateSchema.parse(req.body);
    const agent = await prisma_1.prisma.agent.findFirst({
        where: { id: agentId, userId: req.user.id },
    });
    if (!agent)
        return res.status(404).json({ error: "Agent not found" });
    const quoteDecimals = body.quoteDecimals ?? 6;
    const maxNotionalPerDay = body.maxNotionalPerDay && body.maxNotionalPerDay !== "0"
        ? (0, quantums_1.parseDecimalToBigInt)(body.maxNotionalPerDay, quoteDecimals)
        : 0n;
    const mandate = await prisma_1.prisma.mandate.create({
        data: {
            agentId,
            action: body.action,
            market: body.market ?? null,
            maxNotionalPerDay,
            maxOrdersPerDay: body.maxOrdersPerDay ?? 0,
            notBefore: body.notBefore ? new Date(body.notBefore) : new Date(),
            expiresAt: new Date(body.expiresAt),
            constraints: body.constraints ?? null,
            mandateJwtHash: body.mandateJwtHash ?? null,
            status: "ACTIVE",
        },
    });
    res.json({ ok: true, mandate });
});
// List mandates for an agent you own
router.get("/agents/:agentId", auth_1.requireUser, async (req, res) => {
    const agentId = String(req.params.agentId);
    const agent = await prisma_1.prisma.agent.findFirst({
        where: { id: agentId, userId: req.user.id },
    });
    if (!agent)
        return res.status(404).json({ error: "Agent not found" });
    const mandates = await prisma_1.prisma.mandate.findMany({
        where: { agentId },
        orderBy: { createdAt: "desc" },
    });
    res.json({ ok: true, mandates });
});
// Revoke a mandate
router.post("/:mandateId/revoke", auth_1.requireUser, auth_1.requireMfa, async (req, res) => {
    const mandateId = String(req.params.mandateId);
    // ensure ownership via agent.userId
    const mandate = await prisma_1.prisma.mandate.findUnique({
        where: { id: mandateId },
        include: { agent: true },
    });
    if (!mandate || mandate.agent.userId !== req.user.id) {
        return res.status(404).json({ error: "Mandate not found" });
    }
    await prisma_1.prisma.mandate.update({
        where: { id: mandateId },
        data: { status: "REVOKED", revokedAt: new Date() },
    });
    res.json({ ok: true });
});
exports.default = router;
