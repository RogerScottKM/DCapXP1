"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const require_auth_1 = require("../../middleware/require-auth");
const uploads_controller_1 = require("./uploads.controller");
const router = (0, express_1.Router)();
router.post("/uploads/presign", require_auth_1.requireAuth, uploads_controller_1.presignUpload);
router.post("/uploads/complete", require_auth_1.requireAuth, uploads_controller_1.completeKycUpload);
exports.default = router;
