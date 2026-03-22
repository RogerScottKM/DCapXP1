"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const require_auth_1 = require("../../middleware/require-auth");
const advisor_controller_1 = require("./advisor.controller");
const router = (0, express_1.Router)();
router.get("/advisor/clients/:clientId/aptivio-summary", require_auth_1.requireAuth, advisor_controller_1.getAdvisorClientAptivioSummary);
exports.default = router;
