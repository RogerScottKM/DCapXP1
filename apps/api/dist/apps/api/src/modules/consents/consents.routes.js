"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const require_auth_1 = require("../../middleware/require-auth");
const consents_controller_1 = require("./consents.controller");
const router = (0, express_1.Router)();
router.get("/me/required-consents", require_auth_1.requireAuth, consents_controller_1.getRequiredConsents);
router.post("/me/consents", require_auth_1.requireAuth, consents_controller_1.acceptConsents);
exports.default = router;
