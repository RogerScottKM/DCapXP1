import type { NextFunction, Request, Response } from "express";

import { recordSecurityAudit } from "../lib/service/security-audit";

export function auditPrivilegedRequest(
  action: string,
  resourceType?: string,
  resourceId?: string | ((req: Request) => string | undefined),
  metadataBuilder?: (req: Request) => Record<string, unknown> | undefined,
) {
  return async function auditPrivilegedRequestMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      await recordSecurityAudit({
        actorId: req.auth?.userId ?? null,
        action,
        resourceType: resourceType ?? null,
        resourceId: typeof resourceId === "function" ? resourceId(req) ?? null : resourceId ?? null,
        metadata: metadataBuilder?.(req),
        req,
      });
    } catch (error) {
      console.error("[security-audit] privileged request middleware error", error);
    }

    next();
  };
}
