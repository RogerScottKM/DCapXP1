import type { NextFunction, Request, Response } from "express";

import { ApiError } from "../lib/errors/api-error";
import { prisma } from "../lib/prisma";
import { authService } from "../modules/auth/auth.service";

export type AuthContext = {
  userId: string;
  sessionId?: string;
  roleCodes: string[];
  mfaSatisfied: boolean;
  mfaMethod?: string | null;
  mfaVerifiedAt?: Date | null;
};

declare global {
  namespace Express {
    interface Request {
      auth?: AuthContext;
    }
  }
}

async function buildAuthContext(req: Request): Promise<AuthContext | null> {
  const auth = await authService.resolveAuthFromRequest(req);
  if (!auth) {
    return null;
  }

  const roles = await prisma.roleAssignment.findMany({
    where: { userId: auth.userId },
    select: { roleCode: true },
  });

  return {
    userId: auth.userId,
    sessionId: auth.sessionId,
    roleCodes: roles.map((role) => role.roleCode),
    mfaSatisfied: Boolean(auth.mfaVerifiedAt),
    mfaMethod: auth.mfaMethod ?? null,
    mfaVerifiedAt: auth.mfaVerifiedAt ?? null,
  };
}

async function ensureAuthContext(req: Request, res: Response): Promise<AuthContext> {
  if (!req.auth) {
    await new Promise<void>((resolve, reject) => {
      void requireAuth(req, res, (error?: unknown) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  }

  if (!req.auth) {
    throw new ApiError({
      statusCode: 401,
      code: "UNAUTHENTICATED",
      message: "Authentication required.",
    });
  }

  return req.auth;
}

export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  try {
    const auth = await buildAuthContext(req);
    if (!auth) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    req.auth = auth;
    next();
  } catch (error) {
    next(error);
  }
}

export function requireRole(...allowedRoleCodes: string[]) {
  const allowed = new Set(allowedRoleCodes);

  return async function requireRoleMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      const auth = await ensureAuthContext(req, res);
      const hasRole = auth.roleCodes.some((roleCode) => allowed.has(roleCode));

      if (!hasRole) {
        throw new ApiError({
          statusCode: 403,
          code: "FORBIDDEN",
          message: "You do not have permission to perform this action.",
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireRecentMfa(maxAgeSeconds = 15 * 60) {
  return async function requireRecentMfaMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      const auth = await ensureAuthContext(req, res);
      const verifiedAt = auth.mfaVerifiedAt ? new Date(auth.mfaVerifiedAt).getTime() : 0;
      const ageMs = verifiedAt ? Date.now() - verifiedAt : Number.POSITIVE_INFINITY;
      const isFresh = Number.isFinite(ageMs) && ageMs <= maxAgeSeconds * 1000;

      req.auth = {
        ...auth,
        mfaSatisfied: isFresh,
      };

      if (!isFresh) {
        throw new ApiError({
          statusCode: 401,
          code: "MFA_REQUIRED",
          message: "A recent MFA challenge is required for this action.",
          retryable: true,
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}
