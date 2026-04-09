import { Router } from "express";
import { requireAuth } from "../../middleware/require-auth";
import {
  applyReferralCode,
  getMyReferralStatus,
} from "./referrals.controller";

const router = Router();

router.post("/referrals/apply", requireAuth, applyReferralCode);
router.get("/me/referral-status", requireAuth, getMyReferralStatus);

export default router;
