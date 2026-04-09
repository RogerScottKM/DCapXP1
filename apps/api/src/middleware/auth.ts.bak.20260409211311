import type { NextFunction, Response } from "express";
import { prisma } from "../prisma";

export type AuthedRequest = any & {
  user?: { id: string; username: string };
};

export async function requireUser(req: AuthedRequest, res: Response, next: NextFunction) {
  try {
    const username = String(req.header("x-user") ?? "demo");
    const user = await prisma.user.findUnique({ where: { username } });
    if (!user) return res.status(401).json({ ok: false, error: `unknown user '${username}'` });

    req.user = { id: user.id, username: user.username };
    return next();
  } catch (e: any) {
    return res.status(500).json({ ok: false, error: "auth failed" });
  }
}

// DEV MFA gate: require header x-mfa: ok
export function requireMfa(req: AuthedRequest, res: Response, next: NextFunction) {
  const ok = String(req.header("x-mfa") ?? "").toLowerCase() === "ok";
  if (!ok) return res.status(401).json({ ok: false, error: "mfa required (dev): set header x-mfa: ok" });
  return next();
}

// If any other file imports this name, keep it as a no-op for now.
export function authFromJwt(_req: any, _res: any, next: any) {
  return next();
}
