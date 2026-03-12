import type { Response, NextFunction } from "express";

const secret = new TextEncoder().encode(process.env.JWT_SECRET || "dev_secret_change_me");

export type AuthPayload = {
  sub: string; // userId
  email?: string;
  tenantId?: string;
  roles?: string[];
  [k: string]: any;
};

export async function requireAuth(req: any, res: Response, next: NextFunction) {
  const h = req.headers.authorization || "";
  const token = typeof h === "string" && h.startsWith("Bearer ") ? h.slice(7) : null;

  if (!token) return res.status(401).json({ ok: false, error: "Unauthorized" });

  try {
    const { jwtVerify } = await import("jose");
    const { payload } = await jwtVerify(token, secret);

    req.auth = payload as AuthPayload;
    req.userId = String(payload.sub);

    return next();
  } catch {
    return res.status(401).json({ ok: false, error: "BadToken" });
  }
}

export async function signToken(userId: string, claims: Record<string, any> = {}) {
  const { SignJWT } = await import("jose");

  return await new SignJWT(claims)
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime("30d")
    .sign(secret);
}
