import { Router } from "express";
import type { Response } from "express";
import { z } from "zod";

import { prisma } from "../prisma";
import { requireUser, type AuthedRequest } from "../middleware/auth";
import { requireLiveModeEligible, requireRecentMfa } from "../middleware/require-auth";
import { parseDecimalToBigInt } from "../utils/quantums";

const router = Router();

const issueMandateSchema = z.object({
  action: z.enum(["TRADE", "WITHDRAW", "TRANSFER"]),
  market: z.string().min(3).max(40).optional(),
  maxNotionalPerDay: z.string().optional(),
  quoteDecimals: z.number().int().min(0).max(18).optional(),
  maxOrdersPerDay: z.number().int().min(0).max(1_000_000).optional(),
  notBefore: z.string().datetime().optional(),
  expiresAt: z.string().datetime(),
  constraints: z.any().optional(),
  mandateJwtHash: z.string().optional(),
});

router.post(
  "/agents/:agentId",
  requireUser,
  requireRecentMfa(),
  requireLiveModeEligible(),
  async (req: AuthedRequest, res: Response) => {
    const agentId = String(req.params.agentId);
    const body = issueMandateSchema.parse(req.body);

    const agent = await prisma.agent.findFirst({
      where: { id: agentId, userId: req.user!.id },
    });

    if (!agent) {
      return res.status(404).json({ error: "Agent not found" });
    }

    const quoteDecimals = body.quoteDecimals ?? 6;
    const maxNotionalPerDay = body.maxNotionalPerDay && body.maxNotionalPerDay !== "0"
      ? parseDecimalToBigInt(body.maxNotionalPerDay, quoteDecimals)
      : 0n;

    const mandate = await prisma.mandate.create({
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
  },
);

router.get("/agents/:agentId", requireUser, async (req: AuthedRequest, res: Response) => {
  const agentId = String(req.params.agentId);
  const agent = await prisma.agent.findFirst({ where: { id: agentId, userId: req.user!.id } });

  if (!agent) {
    return res.status(404).json({ error: "Agent not found" });
  }

  const mandates = await prisma.mandate.findMany({ where: { agentId }, orderBy: { createdAt: "desc" } });
  res.json({ ok: true, mandates });
});

router.post("/:mandateId/revoke", requireUser, requireRecentMfa(), async (req: AuthedRequest, res: Response) => {
  const mandateId = String(req.params.mandateId);

  const mandate = await prisma.mandate.findUnique({
    where: { id: mandateId },
    include: { agent: true },
  });

  if (!mandate || mandate.agent.userId !== req.user!.id) {
    return res.status(404).json({ error: "Mandate not found" });
  }

  await prisma.mandate.update({
    where: { id: mandateId },
    data: { status: "REVOKED", revokedAt: new Date() },
  });

  res.json({ ok: true });
});

export default router;
