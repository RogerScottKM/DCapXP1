import argon2 from "argon2";
import crypto from "crypto";
import type { Request, Response } from "express";

export const SESSION_COOKIE_NAME = "dcapx_session";

const SESSION_TTL_DAYS = 30;

export function createSessionSecret(): string {
  return crypto.randomBytes(32).toString("hex");
}

export async function hashSessionSecret(secret: string): Promise<string> {
  return argon2.hash(secret);
}

export async function verifySessionSecret(
  hash: string,
  secret: string
): Promise<boolean> {
  try {
    return await argon2.verify(hash, secret);
  } catch {
    return false;
  }
}

export function buildSessionCookieValue(sessionId: string, secret: string): string {
  return `${sessionId}.${secret}`;
}

export function parseSessionCookieValue(value: string | undefined | null): {
  sessionId: string;
  secret: string;
} | null {
  if (!value) return null;

  const firstDot = value.indexOf(".");
  if (firstDot <= 0) return null;

  const sessionId = value.slice(0, firstDot).trim();
  const secret = value.slice(firstDot + 1).trim();

  if (!sessionId || !secret) return null;

  return { sessionId, secret };
}

export function getCookieFromRequest(req: Request, name: string): string | null {
  const raw = req.headers.cookie;
  if (!raw) return null;

  const parts = raw.split(";").map((part) => part.trim());
  for (const part of parts) {
    const eqIdx = part.indexOf("=");
    if (eqIdx === -1) continue;

    const key = part.slice(0, eqIdx).trim();
    const value = part.slice(eqIdx + 1).trim();

    if (key === name) {
      return decodeURIComponent(value);
    }
  }

  return null;
}

export function getSessionExpiryDate(): Date {
  const d = new Date();
  d.setDate(d.getDate() + SESSION_TTL_DAYS);
  return d;
}

export function setSessionCookie(
  res: Response,
  sessionCookieValue: string,
  expiresAt: Date
) {
  const isProduction = process.env.NODE_ENV === "production";

  res.setHeader(
    "Set-Cookie",
    `${SESSION_COOKIE_NAME}=${encodeURIComponent(
      sessionCookieValue
    )}; Path=/; HttpOnly; SameSite=Lax; ${
      isProduction ? "Secure; " : ""
    }Expires=${expiresAt.toUTCString()}`
  );
}

export function clearSessionCookie(res: Response) {
  const isProduction = process.env.NODE_ENV === "production";

  res.setHeader(
    "Set-Cookie",
    `${SESSION_COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; ${
      isProduction ? "Secure; " : ""
    }Expires=Thu, 01 Jan 1970 00:00:00 GMT`
  );
}
