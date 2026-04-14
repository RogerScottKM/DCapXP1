"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const crypto_1 = __importDefault(require("crypto"));
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const audit_privileged_1 = require("../middleware/audit-privileged");
const auth_1 = require("../middleware/auth");
const require_auth_1 = require("../middleware/require-auth");
const prisma_1 = require("../prisma");
const router = (0, express_1.Router)();
const createAgentSchema = zod_1.z.object({
    name: zod_1.z.string().min(2).max(80),
    kind: zod_1.z.nativeEnum(client_1.AgentKind).optional().default(client_1.AgentKind.MARKET_MAKER),
    aptivioTokenId: zod_1.z.string().optional(),
});
router.post("/", auth_1.requireUser, (0, require_auth_1.requireRecentMfa)(), (0, audit_privileged_1.auditPrivilegedRequest)("AGENT_CREATE_REQUESTED", "AGENT"), async (req, res) => {
    const body = createAgentSchema.parse(req.body);
    const { publicKey, privateKey } = crypto_1.default.generateKeyPairSync("ed25519");
    const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
    const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");
    const agent = await prisma_1.prisma.agent.create({
        data: {
            userId: req.user.id,
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
router.get("/", auth_1.requireUser, async (req, res) => {
    const agents = await prisma_1.prisma.agent.findMany({
        where: { userId: req.user.id },
        include: {
            mandates: true,
            keys: { where: { revokedAt: null } },
        },
        orderBy: { createdAt: "desc" },
    });
    res.json({ ok: true, agents });
});
router.post("/:agentId/keys/rotate", auth_1.requireUser, (0, require_auth_1.requireRecentMfa)(), (0, audit_privileged_1.auditPrivilegedRequest)("AGENT_KEYS_ROTATE_REQUESTED", "AGENT", (req) => String(req.params.agentId)), async (req, res) => {
    const agentId = String(req.params.agentId);
    const agent = await prisma_1.prisma.agent.findFirst({
        where: { id: agentId, userId: req.user.id },
        include: { keys: { where: { revokedAt: null } } },
    });
    if (!agent) {
        return res.status(404).json({ error: "Agent not found" });
    }
    await prisma_1.prisma.agentKey.updateMany({
        where: { agentId, revokedAt: null },
        data: { revokedAt: new Date() },
    });
    const { publicKey, privateKey } = crypto_1.default.generateKeyPairSync("ed25519");
    const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
    const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");
    await prisma_1.prisma.agentKey.create({
        data: { agentId, publicKeyPem },
    });
    res.json({ ok: true, agentId, publicKeyPem, privateKeyPem });
});
router.post("/:agentId/revoke", auth_1.requireUser, (0, require_auth_1.requireRecentMfa)(), (0, audit_privileged_1.auditPrivilegedRequest)("AGENT_REVOKE_REQUESTED", "AGENT", (req) => String(req.params.agentId)), async (req, res) => {
    const agentId = String(req.params.agentId);
    const agent = await prisma_1.prisma.agent.findFirst({
        where: { id: agentId, userId: req.user.id },
    });
    if (!agent) {
        return res.status(404).json({ error: "Agent not found" });
    }
    await prisma_1.prisma.$transaction([
        prisma_1.prisma.agent.update({
            where: { id: agentId },
            data: { status: "REVOKED" },
        }),
        prisma_1.prisma.agentKey.updateMany({
            where: { agentId, revokedAt: null },
            data: { revokedAt: new Date() },
        }),
        prisma_1.prisma.mandate.updateMany({
            where: { agentId, revokedAt: null },
            data: { status: "REVOKED", revokedAt: new Date() },
        }),
    ]);
    res.json({ ok: true });
});
exports.default = router;
