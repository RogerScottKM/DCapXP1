import { Router } from "express";
import { requireAuth } from "../../middleware/require-auth";
import { presignUpload, completeKycUpload } from "./uploads.controller";
const router = Router();
router.post("/uploads/presign", requireAuth, presignUpload);
router.post("/uploads/complete", requireAuth, completeKycUpload);
export default router;
