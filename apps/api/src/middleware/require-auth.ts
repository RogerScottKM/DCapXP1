import type { Request, Response, NextFunction } from "express";
import { ApiError } from "../lib/errors/api-error";

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string };
    }
  }
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  if (!req.auth?.userId) {
    throw new ApiError({
      statusCode: 401,
      code: "UNAUTHENTICATED",
      message: "Authentication required.",
    });
  }
  next();
}
