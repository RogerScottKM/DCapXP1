"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const reconciliation_1 = require("../workers/reconciliation");
const audit_privileged_1 = require("../middleware/audit-privileged");
const require_auth_1 = require("../middleware/require-auth");
const router = (0, express_1.Router)();
router.post("/run", (0, require_auth_1.requireRole)("ADMIN"), (0, require_auth_1.requireRecentMfa)(), (0, audit_privileged_1.auditPrivilegedRequest)("RECONCILIATION_RUN_REQUESTED", "LEDGER"), async (_req, res) => {
    try {
        const results = await (0, reconciliation_1.runReconciliation)();
        const failures = results.filter((r) => !r.ok);
        return res.json({
            ok: failures.length === 0,
            resultCount: results.length,
            failureCount: failures.length,
            results,
        });
    }
    catch (error) {
        return res.status(500).json({
            error: error?.message ?? "Unable to run reconciliation",
        });
    }
});
exports.default = router;
