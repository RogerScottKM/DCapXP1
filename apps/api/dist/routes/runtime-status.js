"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const runtime_status_1 = require("../lib/runtime/runtime-status");
const require_auth_1 = require("../middleware/require-auth");
const router = (0, express_1.Router)();
router.use(require_auth_1.requireAuth);
router.get("/", (0, require_auth_1.requireAdminRecentMfa)(), (_req, res) => {
    return res.json({
        ok: true,
        status: (0, runtime_status_1.getRuntimeStatus)(),
    });
});
exports.default = router;
