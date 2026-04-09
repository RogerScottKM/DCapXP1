"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const require_auth_1 = require("../../middleware/require-auth");
const referrals_controller_1 = require("./referrals.controller");
const router = (0, express_1.Router)();
router.post("/referrals/apply", require_auth_1.requireAuth, referrals_controller_1.applyReferralCode);
router.get("/me/referral-status", require_auth_1.requireAuth, referrals_controller_1.getMyReferralStatus);
exports.default = router;
