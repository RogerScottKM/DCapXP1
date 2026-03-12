"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.enforceMandate = enforceMandate;
exports.bumpOrdersPlaced = bumpOrdersPlaced;
exports.bumpNotionalUsed = bumpNotionalUsed;
const crypto_1 = __importDefault(require("crypto"));
const prisma_1 = require("../infra/prisma");
const canonicalJson_1 = require("../utils/canonicalJson");
const quantums_1 = require("../utils/quantums");
const MAX_SKEW_MS = Number(process.env.IBAC_MAX_SKEW_MS ?? 30_000);
const NONCE_TTL_MS = Number(process.env.IBAC_NONCE_TTL_MS ?? 60_000);
function sha256hex(s) {
    return crypto_1.default.createHash("sha256").update(s).digest("hex");
}
function getSignedPath(req) {
    // baseUrl includes router prefix; path is local.
    return String(req.originalUrl ?? "").split("?")[0]; // exact path client used
}
function verifyEd25519(publicKeyPem, message, signatureB64) {
    try {
        const sig = Buffer.from(signatureB64, "base64");
        const msg = Buffer.from(message, "utf8");
        // For Ed25519 in Node: algorithm is null
        return crypto_1.default.verify(null, msg, publicKeyPem, sig);
    }
    catch {
        return false;
    }
}
async function rejectIfReplay(agentId, nonce, tsMs) {
    // DB-based replay protection: insert unique (agentId, nonce)
    // Also enforce TTL: old nonces rejected.
    const now = Date.now();
    const tsNum = Number(tsMs);
    if (Math.abs(now - tsNum) > MAX_SKEW_MS) {
        throw new Error("STALE_TIMESTAMP");
    }
    // If timestamp is valid, store nonce; duplicates = replay.
    try {
        await prisma_1.prisma.requestNonce.create({
            data: {
                agentId,
                nonce,
                tsMs,
            },
        });
    }
    catch (e) {
        // Prisma unique constraint violation
        if (e?.code === "P2002")
            throw new Error("REPLAY_NONCE");
        throw e;
    }
    // Best-effort cleanup (keep DB small)
    const cutoff = new Date(Date.now() - NONCE_TTL_MS * 10);
    await prisma_1.prisma.requestNonce.deleteMany({ where: { createdAt: { lt: cutoff } } });
}
function enforceMandate(requiredAction) {
    return async (req, res, next) => {
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
            const bodyStable = (0, canonicalJson_1.canonicalStringify)(req.body ?? {});
            const bodyHash = sha256hex(bodyStable);
            const path = getSignedPath(req);
            const msg = `${ts}.${nonce}.${req.method}.${path}.${bodyHash}`;
            const agent = await prisma_1.prisma.agent.findUnique({
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
            if (!activeKey)
                return res.status(403).json({ error: "No active agent key" });
            const okSig = verifyEd25519(activeKey.publicKeyPem, msg, sig);
            if (!okSig) {
                return res.status(403).json({ error: "Invalid agent signature" });
            }
            // Mandate matching
            const now = new Date();
            const targetMarket = String(req.body?.symbol ?? "").toUpperCase().trim();
            const mandate = agent.mandates.find((m) => {
                if (m.action !== requiredAction)
                    return false;
                if (m.notBefore > now)
                    return false;
                if (m.expiresAt <= now)
                    return false;
                if (m.market && m.market !== targetMarket)
                    return false;
                return true;
            });
            if (!mandate) {
                return res.status(403).json({ error: "No valid mandate for action/market" });
            }
            // Daily usage checks (ordersPlaced checked here; notionalUsed should be enforced on fills/ledger)
            const day = (0, quantums_1.utcDay)(now);
            const usage = await prisma_1.prisma.mandateUsage.findUnique({
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
        }
        catch (e) {
            const msg = String(e?.message || "");
            if (msg === "STALE_TIMESTAMP")
                return res.status(401).json({ error: "Stale timestamp" });
            if (msg === "REPLAY_NONCE")
                return res.status(401).json({ error: "Replay nonce" });
            return res.status(500).json({ error: "IBAC verification failed" });
        }
    };
}
// Call this ONLY after an order is actually accepted (idempotently on your side)
async function bumpOrdersPlaced(mandateId) {
    const now = new Date();
    const day = (0, quantums_1.utcDay)(now);
    await prisma_1.prisma.mandateUsage.upsert({
        where: { mandateId_day: { mandateId, day } },
        create: { mandateId, day, ordersPlaced: 1 },
        update: { ordersPlaced: { increment: 1 } },
    });
}
// Call this from your fill/settlement path (quote-asset quantums)
async function bumpNotionalUsed(mandateId, notionalDelta) {
    const now = new Date();
    const day = (0, quantums_1.utcDay)(now);
    await prisma_1.prisma.mandateUsage.upsert({
        where: { mandateId_day: { mandateId, day } },
        create: { mandateId, day, notionalUsed: notionalDelta },
        update: { notionalUsed: { increment: notionalDelta } },
    });
}
