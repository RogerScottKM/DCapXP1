"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuth = requireAuth;
exports.signToken = signToken;
const secret = new TextEncoder().encode(process.env.JWT_SECRET || "dev_secret_change_me");
async function requireAuth(req, res, next) {
    const h = req.headers.authorization || "";
    const token = typeof h === "string" && h.startsWith("Bearer ") ? h.slice(7) : null;
    if (!token)
        return res.status(401).json({ ok: false, error: "Unauthorized" });
    try {
        const { jwtVerify } = await import("jose");
        const { payload } = await jwtVerify(token, secret);
        req.auth = payload;
        req.userId = String(payload.sub);
        return next();
    }
    catch {
        return res.status(401).json({ ok: false, error: "BadToken" });
    }
}
async function signToken(userId, claims = {}) {
    const { SignJWT } = await import("jose");
    return await new SignJWT(claims)
        .setProtectedHeader({ alg: "HS256" })
        .setSubject(userId)
        .setIssuedAt()
        .setExpirationTime("30d")
        .sign(secret);
}
