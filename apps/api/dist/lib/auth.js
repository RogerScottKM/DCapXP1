"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuth = requireAuth;
exports.signToken = signToken;
function getJwtSecret() {
    const value = process.env.JWT_SECRET?.trim();
    if (!value) {
        throw new Error("JWT_SECRET is required");
    }
    return new TextEncoder().encode(value);
}
const JWT_ISSUER = process.env.JWT_ISSUER ?? "dcapx-api";
const JWT_AUDIENCE = process.env.JWT_AUDIENCE ?? "dcapx-clients";
async function requireAuth(req, res, next) {
    const h = req.headers.authorization || "";
    const token = typeof h === "string" && h.startsWith("Bearer ") ? h.slice(7) : null;
    if (!token) {
        return res.status(401).json({ ok: false, error: "Unauthorized" });
    }
    try {
        const { jwtVerify } = await import("jose");
        const { payload } = await jwtVerify(token, getJwtSecret(), {
            issuer: JWT_ISSUER,
            audience: JWT_AUDIENCE,
            algorithms: ["HS256"],
        });
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
        .setIssuer(JWT_ISSUER)
        .setAudience(JWT_AUDIENCE)
        .setSubject(userId)
        .setIssuedAt()
        .setExpirationTime("12h")
        .sign(getJwtSecret());
}
