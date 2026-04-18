"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const matching_events_1 = require("../lib/matching/matching-events");
const runtime_status_1 = require("../lib/runtime/runtime-status");
const require_auth_1 = require("../middleware/require-auth");
const router = (0, express_1.Router)();
router.use(require_auth_1.requireAuth);
router.get("/", (0, require_auth_1.requireAdminRecentMfa)(), (_req, res) => {
    const status = (0, runtime_status_1.getRuntimeStatus)();
    const recentEvents = (0, matching_events_1.listMatchingEvents)(50);
    const lastReconciliationEnvelope = [...recentEvents].reverse().find((event) => event.type === "RECONCILIATION_RESULT") ?? null;
    return res.json({
        ok: true,
        health: {
            runtime: status,
            activeSerializedLanes: status.activeSerializedLanes,
            subscriberCount: (0, matching_events_1.getMatchingEventListenerCount)(),
            recentEventCount: recentEvents.length,
            lastReconciliation: lastReconciliationEnvelope?.payload ?? {
                ok: status.lastReconciliationOk,
                failureCount: status.lastReconciliationFailureCount,
                checkCount: status.lastReconciliationCheckCount,
                ts: status.lastReconciliationAt,
            },
        },
    });
});
exports.default = router;
