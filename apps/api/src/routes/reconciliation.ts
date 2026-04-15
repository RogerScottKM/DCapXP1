import { Router } from "express";

import { runReconciliation } from "../workers/reconciliation";
import { auditPrivilegedRequest } from "../middleware/audit-privileged";
import { requireRecentMfa, requireRole } from "../middleware/require-auth";

const router = Router();

router.post(
  "/run",
  requireRole("ADMIN"),
  requireRecentMfa(),
  auditPrivilegedRequest("RECONCILIATION_RUN_REQUESTED", "LEDGER"),
  async (_req, res) => {
    try {
      const results = await runReconciliation();
      const failures = results.filter((r: { ok: boolean }) => !r.ok);

      return res.json({
        ok: failures.length === 0,
        resultCount: results.length,
        failureCount: failures.length,
        results,
      });
    } catch (error: any) {
      return res.status(500).json({
        error: error?.message ?? "Unable to run reconciliation",
      });
    }
  },
);

export default router;
