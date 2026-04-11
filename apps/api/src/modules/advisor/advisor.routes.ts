import { Router } from "express";
import type { NextFunction, Request, Response } from "express";

import { auditPrivilegedRequest } from "../../middleware/audit-privileged";
import {
  requireAdminRecentMfa,
  requireAuth,
  requireRecentMfa,
  requireRole,
} from "../../middleware/require-auth";
import { getAdvisorClientAptivioSummary } from "./advisor.controller";

const router = Router();

function requireAdvisorOrAdminRecentMfa(req: Request, res: Response, next: NextFunction) {
  const roleCodes = new Set(req.auth?.roleCodes ?? []);

  if (roleCodes.has("admin") || roleCodes.has("auditor")) {
    return requireAdminRecentMfa()(req, res, next);
  }

  return requireRecentMfa()(req, res, next);
}

router.get(
  "/advisor/clients/:clientId/aptivio-summary",
  requireAuth,
  requireRole("advisor", "admin"),
  requireAdvisorOrAdminRecentMfa,
  auditPrivilegedRequest(
    "ADVISOR_CLIENT_APTIVIO_SUMMARY_ACCESSED",
    "USER",
    (req) => String(req.params.clientId),
  ),
  getAdvisorClientAptivioSummary,
);

export default router;
