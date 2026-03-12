import crypto from "crypto";
import { NextFunction, Response } from "express";
import { prisma } from "../infra/prisma";
import { canonicalStringify } from "../utils/canonicalJson";
import { utcDay } from "../utils/quantums";

const MAX_SKEW_MS = Number(process.env.IBAC_MAX_SKEW_MS ?? 30_000);
const NONCE_TTL_MS = Number(process.env.IBAC_NONCE_TTL_MS ?? 60_000);

export type Principal =
  | { type: "AGENT"; userId: string; agentId: string; mandateId: string }
  | { type: "HUMAN"; userId: string };

export type IBACRequest = any & { principal?: Principal };

function sha256hex(s: string) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

function getSignedPath(req: any): string {
  // baseUrl includes router prefix; path is local.
  return String(req.originalUrl ?? "").split("?")[0]; // exact path client used
}
  
function verifyEd25519(publicKeyPem: string, message: string, signatureB64: string): boolean {
  try {
    const sig = Buffer.from(signatureB64, "base64");
    const msg = Buffer.from(message, "utf8");
    // For Ed25519 in Node: algorithm is null
    return crypto.verify(null, msg, publicKeyPem, sig);
  } catch {
    return false;
  }
}

async function rejectIfReplay(agentId: string, nonce: string, tsMs: bigint) {
  // DB-based replay protection: insert unique (agentId, nonce)
  // Also enforce TTL: old nonces rejected.
  const now = Date.now();
  const tsNum = Number(tsMs);
  if (Math.abs(now - tsNum) > MAX_SKEW_MS) {
    throw new Error("STALE_TIMESTAMP");
  }

  // If timestamp is valid, store nonce; duplicates = replay.
  try {
    await prisma.requestNonce.create({
      data: {
        agentId,
        nonce,
        tsMs,
      },
    });
  } catch (e: any) {
    // Prisma unique constraint violation
    if (e?.code === "P2002") throw new Error("REPLAY_NONCE");
    throw e;
  }

  // Best-effort cleanup (keep DB small)
  const cutoff = new Date(Date.now() - NONCE_TTL_MS * 10);
  await prisma.requestNonce.deleteMany({ where: { createdAt: { lt: cutoff } } });
}

export function enforceMandate(requiredAction: "TRADE" | "WITHDRAW" | "TRANSFER") {
  return async (req: IBACRequest, res: Response, next: NextFunction) => {
    try {
      const agentId = req.header("x-agent-id");
      const ts = req.header("x-agent-ts");
      const nonce = req.header("x-agent-nonce");
      const sig = req.header("x-agent-sig");

      if (!agentId || !ts || !nonce || !sig) {
        return res.status(401).json({ error: "Missing agent auth headers" });
      }

      const tsMs = BigInt(ts);
      await rejectIfReplay(agentId, nonce, tsMs);

      const bodyStable = canonicalStringify(req.body ?? {});
      const bodyHash = sha256hex(bodyStable);

      const path = getSignedPath(req);
      const msg = `${ts}.${nonce}.${req.method}.${path}.${bodyHash}`;

      const agent = await prisma.agent.findUnique({
        where: { id: agentId },
        include: {
          user: true,
          keys: { where: { revokedAt: null }, orderBy: { createdAt: "desc" } },
          mandates: {
            where: { status: "ACTIVE", revokedAt: null },
            orderBy: { createdAt: "desc" },
          },
        },
      });

      if (!agent || agent.status !== "ACTIVE") {
        return res.status(403).json({ error: "Agent invalid/revoked" });
      }

      const activeKey = agent.keys[0];
      if (!activeKey) return res.status(403).json({ error: "No active agent key" });

      const okSig = verifyEd25519(activeKey.publicKeyPem, msg, sig);
      if (!okSig) {
        return res.status(403).json({ error: "Invalid agent signature" });
      }

      // Mandate matching
      const now = new Date();
      const targetMarket = String(req.body?.symbol ?? "").toUpperCase().trim(); 
      const mandate = agent.mandates.find((m) => {
        if (m.action !== requiredAction) return false;
        if (m.notBefore > now) return false;
        if (m.expiresAt <= now) return false;
        if (m.market && m.market !== targetMarket) return false;
        return true;
      });

      if (!mandate) {
        return res.status(403).json({ error: "No valid mandate for action/market" });
      }

      // Daily usage checks (ordersPlaced checked here; notionalUsed should be enforced on fills/ledger)
      const day = utcDay(now);
      const usage = await prisma.mandateUsage.findUnique({
        where: { mandateId_day: { mandateId: mandate.id, day } },
      });

      if (mandate.maxOrdersPerDay > 0 && (usage?.ordersPlaced ?? 0) >= mandate.maxOrdersPerDay) {
        return res.status(403).json({ error: "Mandate maxOrdersPerDay exceeded" });
      }

      // Attach principal context
      req.principal = {
        type: "AGENT",
        userId: agent.userId,
        agentId: agent.id,
        mandateId: mandate.id,
      };

      next();
    } catch (e: any) {
      const msg = String(e?.message || "");
      if (msg === "STALE_TIMESTAMP") return res.status(401).json({ error: "Stale timestamp" });
      if (msg === "REPLAY_NONCE") return res.status(401).json({ error: "Replay nonce" });
      return res.status(500).json({ error: "IBAC verification failed" });
    }
  };
}

// Call this ONLY after an order is actually accepted (idempotently on your side)
export async function bumpOrdersPlaced(mandateId: string) {
  const now = new Date();
  const day = utcDay(now);
  await prisma.mandateUsage.upsert({
    where: { mandateId_day: { mandateId, day } },
    create: { mandateId, day, ordersPlaced: 1 },
    update: { ordersPlaced: { increment: 1 } },
  });
}

// Call this from your fill/settlement path (quote-asset quantums)
export async function bumpNotionalUsed(mandateId: string, notionalDelta: bigint) {
  const now = new Date();
  const day = utcDay(now);
  await prisma.mandateUsage.upsert({
    where: { mandateId_day: { mandateId, day } },
    create: { mandateId, day, notionalUsed: notionalDelta },
    update: { notionalUsed: { increment: notionalDelta } },
  });
}
