import { Router } from "express";
import { requireAuth } from "../../middleware/require-auth";
import { createInvitation, getInvitationByToken, acceptInvitation } from "./invitations.controller";

const router = Router();
router.post("/advisor/invitations", requireAuth, createInvitation);
router.get("/invitations/:token", getInvitationByToken);
router.post("/invitations/:token/accept", requireAuth, acceptInvitation);
export default router;
