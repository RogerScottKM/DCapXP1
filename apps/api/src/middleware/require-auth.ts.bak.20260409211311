import type { Request, Response, NextFunction } from "express";
import { ApiError } from "../lib/errors/api-error";
import { authService } from "../modules/auth/auth.service";

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; sessionId?: string };
    }
  }
}

export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  try {
    const auth = await authService.resolveAuthFromRequest(req);

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
