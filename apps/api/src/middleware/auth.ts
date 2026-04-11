import type { NextFunction, Request, Response } from "express";

import { ApiError } from "../lib/errors/api-error";
import type { AuthContext } from "./require-auth";
import { requireAuth, requireRecentMfa, requireAdminRecentMfa } from "./require-auth";

export type AuthedRequest = Request & {
  auth?: AuthContext;
  user?: { id: string; username: string };
};

export async function requireUser(req: AuthedRequest, res: Response, next: NextFunction) {
  try {
    await new Promise<void>((resolve, reject) => {
      void requireAuth(req, res, (error?: unknown) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });

    if (!req.auth) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    req.user = {
      id: req.auth.userId,
      username: req.auth.userId,
    };

    next();
  } catch (error) {
    next(error);
  }
}

export const requireMfa = requireRecentMfa();
export const requireAdminMfa = requireAdminRecentMfa();

export function authFromJwt(_req: Request, _res: Response, next: NextFunction) {
  next(
    new ApiError({
      statusCode: 501,
      code: "LEGACY_AUTH_DISABLED",
      message:
        "Legacy auth middleware is disabled. Use the canonical session-based require-auth middleware instead.",
    }),
  );
}
