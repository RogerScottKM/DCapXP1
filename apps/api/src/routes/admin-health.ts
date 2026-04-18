import { Router } from "express";

import {
  getMatchingEventListenerCount,
  listMatchingEvents,
} from "../lib/matching/matching-events";
import { getRuntimeStatus } from "../lib/runtime/runtime-status";
import { requireAuth, requireAdminRecentMfa } from "../middleware/require-auth";

const router = Router();

router.use(requireAuth);

router.get("/", requireAdminRecentMfa(), (_req, res) => {
  const status = getRuntimeStatus();
  const recentEvents = listMatchingEvents(50);
  const lastReconciliationEnvelope =
    [...recentEvents].reverse().find((event) => event.type === "RECONCILIATION_RESULT") ?? null;

  return res.json({
    ok: true,
    health: {
      runtime: status,
      activeSerializedLanes: status.activeSerializedLanes,
      subscriberCount: getMatchingEventListenerCount(),
      recentEventCount: recentEvents.length,
      lastReconciliation:
        lastReconciliationEnvelope?.payload ?? {
          ok: status.lastReconciliationOk,
          failureCount: status.lastReconciliationFailureCount,
          checkCount: status.lastReconciliationCheckCount,
          ts: status.lastReconciliationAt,
        },
    },
  });
});

export default router;
