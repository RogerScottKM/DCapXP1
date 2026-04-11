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

function getMfaAgeMs(auth: AuthContext): number {
  const verifiedAt = auth.mfaVerifiedAt ? new Date(auth.mfaVerifiedAt).getTime() : 0;
  return verifiedAt ? Date.now() - verifiedAt : Number.POSITIVE_INFINITY;
}

function isRecentMfa(auth: AuthContext, maxAgeSeconds: number): boolean {
  const ageMs = getMfaAgeMs(auth);
  return Number.isFinite(ageMs) && ageMs <= maxAgeSeconds * 1000;
}

function getRequestedMode(req: Request): string | undefined {
  const bodyMode = typeof req.body?.mode === "string" ? req.body.mode : undefined;
  const queryMode =
    typeof req.query?.mode === "string"
      ? req.query.mode
      : Array.isArray(req.query?.mode)
        ? req.query.mode[0]
        : undefined;
  const headerMode = typeof req.headers["x-mode"] === "string" ? req.headers["x-mode"] : undefined;

  const mode = bodyMode ?? queryMode ?? headerMode;
  return mode ? String(mode).trim().toUpperCase() : undefined;
}

async function hasApprovedLiveEligibility(userId: string): Promise<boolean> {
  const approvedKycCase = await prisma.kycCase.findFirst({
    where: {
      userId,
      status: "APPROVED" as any,
    },
    select: { id: true },
    orderBy: { updatedAt: "desc" },
  });

  if (approvedKycCase) {
    return true;
  }

  const legacyKycDelegate = (prisma as any).kyc;
  if (legacyKycDelegate?.findFirst) {
    const approvedLegacyKyc = await legacyKycDelegate.findFirst({
      where: {
        userId,
        status: "APPROVED",
      },
      select: { id: true },
      orderBy: { updatedAt: "desc" },
    });

    if (approvedLegacyKyc) {
      return true;
    }
  }

  return false;
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
      const fresh = isRecentMfa(auth, maxAgeSeconds);

      req.auth = {
        ...auth,
        mfaSatisfied: fresh,
      };

      if (!fresh) {
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

export function requireAdminRecentMfa(
  allowedRoleCodes: string[] = ["ADMIN", "AUDITOR"],
  maxAgeSeconds = 15 * 60,
) {
  return async function requireAdminRecentMfaMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      const auth = await ensureAuthContext(req, res);
      const allowed = new Set(allowedRoleCodes);
      const hasRole = auth.roleCodes.some((roleCode) => allowed.has(roleCode));

      if (!hasRole) {
        throw new ApiError({
          statusCode: 403,
          code: "FORBIDDEN",
          message: "Administrator or auditor access is required.",
        });
      }

      const fresh = isRecentMfa(auth, maxAgeSeconds);

      req.auth = {
        ...auth,
        mfaSatisfied: fresh,
      };

      if (!fresh) {
        throw new ApiError({
          statusCode: 401,
          code: "MFA_REQUIRED",
          message: "A recent MFA challenge is required for administrative access.",
          retryable: true,
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireLiveModeEligible(maxAgeSeconds = 15 * 60) {
  return async function requireLiveModeEligibleMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      const requestedMode = getRequestedMode(req);
      if (requestedMode !== "LIVE") {
        return next();
      }

      const auth = await ensureAuthContext(req, res);
      const fresh = isRecentMfa(auth, maxAgeSeconds);

      req.auth = {
        ...auth,
        mfaSatisfied: fresh,
      };

      if (!fresh) {
        throw new ApiError({
          statusCode: 401,
          code: "MFA_REQUIRED",
          message: "A recent MFA challenge is required for LIVE mode.",
          retryable: true,
        });
      }

      const liveEligible = await hasApprovedLiveEligibility(auth.userId);
      if (!liveEligible) {
        throw new ApiError({
          statusCode: 403,
          code: "LIVE_MODE_NOT_ALLOWED",
          message: "Approved KYC is required for LIVE mode.",
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}
