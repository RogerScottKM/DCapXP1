import crypto from "crypto";
import type { Request } from "express";

export function getAdminKey(): string {
  const value = process.env.ADMIN_KEY?.trim();
  if (!value) {
    throw new Error("ADMIN_KEY is required");
  }
  return value;
}

function readHeader(req: Pick<Request, "header" | "headers">, name: string): string | undefined {
  if (typeof req.header === "function") {
    const value = req.header(name);
    return typeof value === "string" ? value : undefined;
  }

  const raw = (req.headers as Record<string, unknown> | undefined)?.[name.toLowerCase()];
  if (Array.isArray(raw)) {
    return typeof raw[0] === "string" ? raw[0] : undefined;
  }
  return typeof raw === "string" ? raw : undefined;
}

function timingSafeEqualString(a: string, b: string): boolean {
  const aBuf = Buffer.from(a);
  const bBuf = Buffer.from(b);
  if (aBuf.length !== bBuf.length) {
    return false;
  }
  return crypto.timingSafeEqual(aBuf, bBuf);
}

/**
 * Backward-compatible helper for older admin-key protected routes.
 * Cleanup B will replace these routes with RBAC + MFA, but for now
 * we keep this named export so the old imports still compile.
 */
export function isAdmin(req: Pick<Request, "header" | "headers">): boolean {
  const provided = readHeader(req, "x-admin-key")?.trim();
  if (!provided) {
    return false;
  }

  const expected = getAdminKey();
  return timingSafeEqualString(provided, expected);
}

export default getAdminKey;
