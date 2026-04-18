"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.withIdempotency = withIdempotency;
const node_crypto_1 = require("node:crypto");
const prisma_1 = require("./prisma");
function stableSerialize(value) {
    if (value === null || value === undefined)
        return "null";
    if (typeof value !== "object")
        return JSON.stringify(value);
    if (Array.isArray(value)) {
        return "[" + value.map((v) => stableSerialize(v)).join(",") + "]";
    }
    const entries = Object.entries(value)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => `${JSON.stringify(k)}:${stableSerialize(v)}`);
    return "{" + entries.join(",") + "}";
}
function readIdempotencyKey(req) {
    const raw = req.get?.("Idempotency-Key") ??
        req.header?.("Idempotency-Key") ??
        (typeof req.headers["idempotency-key"] === "string"
            ? req.headers["idempotency-key"]
            : Array.isArray(req.headers["idempotency-key"])
                ? req.headers["idempotency-key"][0]
                : null);
    const key = String(raw ?? "").trim();
    return key.length > 0 ? key : null;
}
function getOwner(req) {
    const auth = req.auth;
    if (auth?.userId) {
        return { ownerType: "USER", ownerId: String(auth.userId) };
    }
    const principal = req.principal;
    if (principal?.userId) {
        return { ownerType: String(principal.type ?? "AGENT"), ownerId: String(principal.userId) };
    }
    return null;
}
function hashRequest(req) {
    const payload = {
        method: req.method,
        path: req.path,
        params: req.params ?? {},
        query: req.query ?? {},
        body: req.body ?? {},
    };
    return (0, node_crypto_1.createHash)("sha256").update(stableSerialize(payload)).digest("hex");
}
async function findRecord(input) {
    return prisma_1.prisma.idempotencyKey.findUnique({
        where: {
            ownerType_ownerId_scope_key: {
                ownerType: input.ownerType,
                ownerId: input.ownerId,
                scope: input.scope,
                key: input.key,
            },
        },
    });
}
async function createPending(input) {
    return prisma_1.prisma.idempotencyKey.create({
        data: {
            ownerType: input.ownerType,
            ownerId: input.ownerId,
            scope: input.scope,
            key: input.key,
            requestHash: input.requestHash,
            method: input.method,
            path: input.path,
            state: "PENDING",
        },
    });
}
async function markCompleted(id, responseStatus, responseBody) {
    await prisma_1.prisma.idempotencyKey.update({
        where: { id },
        data: {
            state: "COMPLETED",
            responseStatus,
            responseBody: (responseBody ?? null),
        },
    });
}
async function clearPending(id) {
    await prisma_1.prisma.idempotencyKey.delete({ where: { id } }).catch(() => undefined);
}
function withIdempotency(scope, handler) {
    return async (req, res) => {
        const key = readIdempotencyKey(req);
        if (!key) {
            return handler(req, res);
        }
        const owner = getOwner(req);
        if (!owner) {
            return res.status(401).json({ error: "Authentication required." });
        }
        const input = {
            ownerType: owner.ownerType,
            ownerId: owner.ownerId,
            scope,
            key,
            requestHash: hashRequest(req),
            method: req.method,
            path: req.path,
        };
        let existing = await findRecord(input);
        if (existing) {
            if (existing.requestHash !== input.requestHash) {
                return res.status(409).json({
                    error: "Idempotency key reuse with different payload.",
                });
            }
            if (existing.state === "COMPLETED") {
                return res.status(existing.responseStatus ?? 200).json(existing.responseBody ?? { ok: true });
            }
            return res.status(409).json({
                error: "Idempotency request is already in progress.",
            });
        }
        try {
            existing = await createPending(input);
        }
        catch (error) {
            if (error?.code === "P2002") {
                existing = await findRecord(input);
                if (existing?.requestHash !== input.requestHash) {
                    return res.status(409).json({
                        error: "Idempotency key reuse with different payload.",
                    });
                }
                if (existing?.state === "COMPLETED") {
                    return res.status(existing.responseStatus ?? 200).json(existing.responseBody ?? { ok: true });
                }
                return res.status(409).json({
                    error: "Idempotency request is already in progress.",
                });
            }
            throw error;
        }
        let capturedStatus = 200;
        let capturedBody;
        const originalStatus = res.status.bind(res);
        const originalJson = res.json.bind(res);
        res.status = (code) => {
            capturedStatus = code;
            return originalStatus(code);
        };
        res.json = (body) => {
            capturedBody = body;
            return originalJson(body);
        };
        try {
            const result = await handler(req, res);
            await markCompleted(existing.id, capturedStatus, capturedBody);
            return result;
        }
        catch (error) {
            await clearPending(existing.id);
            throw error;
        }
    };
}
