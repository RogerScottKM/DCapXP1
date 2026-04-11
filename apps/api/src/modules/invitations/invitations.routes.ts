import { Router } from "express";
import type { NextFunction, Request, Response } from "express";

import {
  requireAdminRecentMfa,
  requireAuth,
  requireRecentMfa,
  requireRole,
} from "../../middleware/require-auth";
import { acceptInvitation, createInvitation, getInvitationByToken } from "./invitations.controller";

const router = Router();

function requireAdvisorOrAdminRecentMfa(req: Request, res: Response, next: NextFunction) {
  const roleCodes = new Set(req.auth?.roleCodes ?? []);
  if (roleCodes.has("admin") || roleCodes.has("auditor")) {
    return requireAdminRecentMfa()(req, res, next);
  }
  return requireRecentMfa()(req, res, next);
}

router.post(
  "/advisor/invitations",
  requireAuth,
  requireRole("advisor", "admin"),
  requireAdvisorOrAdminRecentMfa,
  createInvitation,
);
router.get("/invitations/:token", getInvitationByToken);
router.post("/invitations/:token/accept", requireAuth, acceptInvitation);

export default router;
