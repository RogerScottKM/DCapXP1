"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const require_auth_1 = require("../../middleware/require-auth");
const kyc_controller_1 = require("./kyc.controller");
const router = (0, express_1.Router)();
router.get("/me/kyc-case", require_auth_1.requireAuth, kyc_controller_1.getMyKycCase);
router.post("/me/kyc-cases", require_auth_1.requireAuth, kyc_controller_1.createMyKycCase);
exports.default = router;
