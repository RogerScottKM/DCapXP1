"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireUser = requireUser;
exports.requireMfa = requireMfa;
exports.authFromJwt = authFromJwt;
const prisma_1 = require("../prisma");
async function requireUser(req, res, next) {
    try {
        const username = String(req.header("x-user") ?? "demo");
        const user = await prisma_1.prisma.user.findUnique({ where: { username } });
        if (!user)
            return res.status(401).json({ ok: false, error: `unknown user '${username}'` });
        req.user = { id: user.id, username: user.username };
        return next();
    }
    catch (e) {
        return res.status(500).json({ ok: false, error: "auth failed" });
    }
}
// DEV MFA gate: require header x-mfa: ok
function requireMfa(req, res, next) {
    const ok = String(req.header("x-mfa") ?? "").toLowerCase() === "ok";
    if (!ok)
        return res.status(401).json({ ok: false, error: "mfa required (dev): set header x-mfa: ok" });
    return next();
}
// If any other file imports this name, keep it as a no-op for now.
function authFromJwt(_req, _res, next) {
    return next();
}
