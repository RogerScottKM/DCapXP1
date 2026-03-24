import { Router } from "express";
import { requireAuth } from "../../middleware/require-auth";
import { createMyKycCase, getMyKycCase } from "./kyc.controller";

const router = Router();

router.get("/me/kyc-case", requireAuth, getMyKycCase);
router.post("/me/kyc-cases", requireAuth, createMyKycCase);

export default router;
