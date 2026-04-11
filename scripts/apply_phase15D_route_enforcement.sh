#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def write(path_str: str, content: str):
    p = root / path_str
    p.write_text(content)

# Overwrite compact route files with cleaner guarded versions.
write("apps/api/src/routes/agents.ts", '''import { Router } from "express";
import type { Response } from "express";
import crypto from "crypto";
import { z } from "zod";
import { AgentKind } from "@prisma/client";

import { prisma } from "../prisma";
import { requireUser, type AuthedRequest } from "../middleware/auth";
import { requireRecentMfa } from "../middleware/require-auth";

const router = Router();

const createAgentSchema = z.object({
  name: z.string().min(2).max(80),
  kind: z.nativeEnum(AgentKind).optional().default(AgentKind.MARKET_MAKER),
  aptivioTokenId: z.string().optional(),
});

router.post("/", requireUser, requireRecentMfa(), async (req: AuthedRequest, res: Response) => {
  const body = createAgentSchema.parse(req.body);

  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
  const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");

  const agent = await prisma.agent.create({
    data: {
      userId: req.user!.id,
      name: body.name,
      kind: body.kind,
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
    privateKeyPem,
  });
});

router.get("/", requireUser, async (req: AuthedRequest, res: Response) => {
  const agents = await prisma.agent.findMany({
    where: { userId: req.user!.id },
    include: { mandates: true, keys: { where: { revokedAt: null } } },
    orderBy: { createdAt: "desc" },
  });

  res.json({ ok: true, agents });
});

router.post("/:agentId/keys/rotate", requireUser, requireRecentMfa(), async (req: AuthedRequest, res: Response) => {
  const agentId = String(req.params.agentId);

  const agent = await prisma.agent.findFirst({
    where: { id: agentId, userId: req.user!.id },
    include: { keys: { where: { revokedAt: null } } },
  });

  if (!agent) {
    return res.status(404).json({ error: "Agent not found" });
  }

  await prisma.agentKey.updateMany({
    where: { agentId, revokedAt: null },
    data: { revokedAt: new Date() },
  });

  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
  const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");

  await prisma.agentKey.create({ data: { agentId, publicKeyPem } });

  res.json({ ok: true, agentId, publicKeyPem, privateKeyPem });
});

router.post("/:agentId/revoke", requireUser, requireRecentMfa(), async (req: AuthedRequest, res: Response) => {
  const agentId = String(req.params.agentId);
  const agent = await prisma.agent.findFirst({ where: { id: agentId, userId: req.user!.id } });

  if (!agent) {
    return res.status(404).json({ error: "Agent not found" });
  }

  await prisma.$transaction([
    prisma.agent.update({ where: { id: agentId }, data: { status: "REVOKED" } }),
    prisma.agentKey.updateMany({ where: { agentId, revokedAt: null }, data: { revokedAt: new Date() } }),
    prisma.mandate.updateMany({
      where: { agentId, revokedAt: null },
      data: { status: "REVOKED", revokedAt: new Date() },
    }),
  ]);

  res.json({ ok: true });
});

export default router;
''')

write("apps/api/src/routes/mandates.ts", '''import { Router } from "express";
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
''')

write("apps/api/src/modules/advisor/advisor.routes.ts", '''import { Router } from "express";
import type { NextFunction, Request, Response } from "express";

import {
  requireAdminRecentMfa,
  requireAuth,
  requireRecentMfa,
  requireRole,
} from "../../middleware/require-auth";
import { getAdvisorClientAptivioSummary } from "./advisor.controller";

const router = Router();

function requireAdvisorOrAdminRecentMfa(req: Request, res: Response, next: NextFunction) {
  const roleCodes = new Set(req.auth?.roleCodes ?? []);
  if (roleCodes.has("admin") || roleCodes.has("auditor")) {
    return requireAdminRecentMfa()(req, res, next);
  }
  return requireRecentMfa()(req, res, next);
}

router.get(
  "/advisor/clients/:clientId/aptivio-summary",
  requireAuth,
  requireRole("advisor", "admin"),
  requireAdvisorOrAdminRecentMfa,
  getAdvisorClientAptivioSummary,
);

export default router;
''')

write("apps/api/src/modules/invitations/invitations.routes.ts", '''import { Router } from "express";
import type { NextFunction, Request, Response } from "express";

import {
  requireAdminRecentMfa,
  requireAuth,
  requireRecentMfa,
  requireRole,
} from "../../middleware/require-auth";
import { acceptInvitation, createInvitation, getInvitationByToken } from "./invitations.controller";

const router = Router();

function requireAdvisorOrAdminRecentMfa(req: Request, res: Response, next: NextFunction) {
  const roleCodes = new Set(req.auth?.roleCodes ?? []);
  if (roleCodes.has("admin") || roleCodes.has("auditor")) {
    return requireAdminRecentMfa()(req, res, next);
  }
  return requireRecentMfa()(req, res, next);
}

router.post(
  "/advisor/invitations",
  requireAuth,
  requireRole("advisor", "admin"),
  requireAdvisorOrAdminRecentMfa,
  createInvitation,
);
router.get("/invitations/:token", getInvitationByToken);
router.post("/invitations/:token/accept", requireAuth, acceptInvitation);

export default router;
''')

print("Patched agents.ts, mandates.ts, advisor.routes.ts, and invitations.routes.ts for Pass 1.5D route enforcement.")
PY

echo "Pass 1.5D patch applied."
