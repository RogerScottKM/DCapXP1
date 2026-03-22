import { Router } from "express";
import { requireAuth } from "../../middleware/require-auth";
import { getRequiredConsents, acceptConsents } from "./consents.controller";
const router = Router();
router.get("/me/required-consents", requireAuth, getRequiredConsents);
router.post("/me/consents", requireAuth, acceptConsents);
export default router;
