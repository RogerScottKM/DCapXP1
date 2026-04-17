import { Router } from "express";

import { getRuntimeStatus } from "../lib/runtime/runtime-status";
import { requireAuth, requireAdminRecentMfa } from "../middleware/require-auth";

const router = Router();

router.use(requireAuth);

router.get("/", requireAdminRecentMfa(), (_req, res) => {
  return res.json({
    ok: true,
    status: getRuntimeStatus(),
  });
});

export default router;
