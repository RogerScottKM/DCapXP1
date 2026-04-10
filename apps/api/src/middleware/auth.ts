import type { NextFunction, Request, Response } from "express";
import { ApiError } from "../lib/errors/api-error";
import { authService } from "../modules/auth/auth.service";

export type AuthedRequest = Request & {
  auth?: { userId: string; sessionId?: string };
  user?: { id: string; username: string };
};

export async function requireUser(req: AuthedRequest, _res: Response, next: NextFunction) {
  try {
    const auth = await authService.resolveAuthFromRequest(req);

    if (!auth) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    req.auth = {
      userId: auth.userId,
      sessionId: auth.sessionId,
      roleCodes: "roleCodes" in auth && Array.isArray((auth as any).roleCodes) ? (auth as any).roleCodes : [],
      mfaSatisfied: "mfaSatisfied" in auth ? Boolean((auth as any).mfaSatisfied) : false,
    };
    req.user = { id: auth.userId, username: auth.userId };
    next();
  } catch (error) {
    next(error);
  }
}

export function requireMfa(_req: AuthedRequest, _res: Response, next: NextFunction) {
  next(
    new ApiError({
      statusCode: 501,
      code: "MFA_NOT_IMPLEMENTED",
      message:
        "Legacy development MFA bypass has been disabled. Wire this route to real TOTP/session step-up before enabling it in production.",
    })
  );
}

export function authFromJwt(_req: Request, _res: Response, next: NextFunction) {
  next(
    new ApiError({
      statusCode: 501,
      code: "LEGACY_AUTH_DISABLED",
      message:
        "Legacy auth middleware is disabled. Use the canonical session-based require-auth middleware instead.",
    })
  );
}
