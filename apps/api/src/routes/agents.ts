import { Router } from "express";
import type { Response } from "express";
import crypto from "crypto";
import { z } from "zod";
import { AgentKind } from "@prisma/client";
import { prisma } from "../prisma";
import { requireMfa, requireUser, AuthedRequest } from "../middleware/auth";

const router = Router();

const createAgentSchema = z.object({
  name: z.string().min(2).max(80),
  kind: z.nativeEnum(AgentKind).optional().default(AgentKind.MARKET_MAKER),
  aptivioTokenId: z.string().optional(),
});

// Create a new agent + issue an Ed25519 keypair (private key returned ONCE)
router.post("/", requireUser, requireMfa, async (req: AuthedRequest, res: Response) => {
  const body = createAgentSchema.parse(req.body);

  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
  const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");

  const agent = await prisma.agent.create({
    data: {
      userId: req.user!.id,
      name: body.name,
      kind: body.kind, // ✅ REQUIRED
      aptivioTokenId: body.aptivioTokenId ?? null,
      keys: {
        create: {
          publicKeyPem,
        },
      },
    },
    include: { keys: true },
  });

  return res.json({
    ok: true,
    agent: {
      id: agent.id,
      name: agent.name,
      status: agent.status,
      publicKeyPem,
    },
    // WARNING: store this securely; you cannot recover it later
    privateKeyPem,
  });
});

// List your agents
router.get("/", requireUser, async (req: AuthedRequest, res: Response) => {
  const agents = await prisma.agent.findMany({
    where: { userId: req.user!.id },
    include: { mandates: true, keys: { where: { revokedAt: null } } },
    orderBy: { createdAt: "desc" },
  });

  res.json({ ok: true, agents });
});

// Rotate keys (revoke old + issue new private key ONCE)
router.post("/:agentId/keys/rotate", requireUser, requireMfa, async (req: AuthedRequest, res: Response) => {
  const agentId = String(req.params.agentId);

  const agent = await prisma.agent.findFirst({
    where: { id: agentId, userId: req.user!.id },
    include: { keys: { where: { revokedAt: null } } },
  });
  if (!agent) return res.status(404).json({ error: "Agent not found" });

  // revoke current keys
  await prisma.agentKey.updateMany({
    where: { agentId, revokedAt: null },
    data: { revokedAt: new Date() },
  });

  // issue new pair
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
  const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");

  await prisma.agentKey.create({
    data: { agentId, publicKeyPem },
  });

  res.json({
    ok: true,
    agentId,
    publicKeyPem,
    privateKeyPem, // return ONCE
  });
});

// Revoke agent (and all keys/mandates)
router.post("/:agentId/revoke", requireUser, requireMfa, async (req: AuthedRequest, res: Response) => {
  const agentId = String(req.params.agentId);

  const agent = await prisma.agent.findFirst({ where: { id: agentId, userId: req.user!.id } });
  if (!agent) return res.status(404).json({ error: "Agent not found" });

  await prisma.$transaction([
    prisma.agent.update({ where: { id: agentId }, data: { status: "REVOKED" } }),
    prisma.agentKey.updateMany({ where: { agentId, revokedAt: null }, data: { revokedAt: new Date() } }),
    prisma.mandate.updateMany({ where: { agentId, revokedAt: null }, data: { status: "REVOKED", revokedAt: new Date() } }),
  ]);

  res.json({ ok: true });
});

export default router;
