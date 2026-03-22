"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const require_auth_1 = require("../../middleware/require-auth");
const onboarding_controller_1 = require("./onboarding.controller");
const router = (0, express_1.Router)();
router.get("/me/onboarding-status", require_auth_1.requireAuth, onboarding_controller_1.getMyOnboardingStatus);
exports.default = router;
