"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// apps/api/src/routes/agentic.ts
const express_1 = require("express");
const plan_1 = require("../agentic/plan");
const router = (0, express_1.Router)();
/**
 * GET /plan
 * Mounted at:
 *  - /api/v1/ui  => /api/v1/ui/plan
 *  - /v1/ui      => /v1/ui/plan
 */
router.get("/plan", (req, res) => {
    const plan = (0, plan_1.generateUIPlan)({
        userId: req.query.userId,
        intent: req.query.intent,
        symbol: req.query.symbol,
    });
    res.json(plan);
});
exports.default = router;
