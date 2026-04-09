"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const verification_service_1 = require("./verification.service");
const simple_rate_limit_1 = require("../../middleware/simple-rate-limit");
const router = (0, express_1.Router)();
const publicLimiter = (0, simple_rate_limit_1.simpleRateLimit)({ keyPrefix: "verification:public", windowMs: 10 * 60 * 1000, max: 10 });
router.post("/auth/verify-email/request", publicLimiter, async (req, res) => {
    try {
        const email = String(req.body?.email ?? "").trim();
        if (!email) {
            return res.status(400).json({
                error: { code: "EMAIL_REQUIRED", message: "Email is required." },
            });
        }
        const result = await verification_service_1.verificationService.requestEmailVerification(email);
        return res.json(result);
    }
    catch (error) {
        return res.status(500).json({
            error: {
                code: "VERIFY_EMAIL_REQUEST_FAILED",
                message: error?.message ?? "Failed to request verification email.",
            },
        });
    }
});
router.post("/auth/verify-email/confirm", publicLimiter, async (req, res) => {
    try {
        const email = String(req.body?.email ?? "").trim();
        const code = String(req.body?.code ?? "").trim();
        if (!email || !code) {
            return res.status(400).json({
                error: { code: "EMAIL_AND_CODE_REQUIRED", message: "Email and code are required." },
            });
        }
        const result = await verification_service_1.verificationService.confirmEmailVerification(email, code);
        return res.json(result);
    }
    catch (error) {
        return res.status(400).json({
            error: {
                code: "VERIFY_EMAIL_CONFIRM_FAILED",
                message: error?.message ?? "Failed to verify email.",
            },
        });
    }
});
router.post("/auth/password/forgot", publicLimiter, async (req, res) => {
    try {
        const email = String(req.body?.email ?? "").trim();
        if (!email) {
            return res.status(400).json({
                error: { code: "EMAIL_REQUIRED", message: "Email is required." },
            });
        }
        const result = await verification_service_1.verificationService.requestPasswordReset(email);
        return res.json(result);
    }
    catch (error) {
        return res.status(500).json({
            error: {
                code: "PASSWORD_FORGOT_FAILED",
                message: error?.message ?? "Failed to request password reset.",
            },
        });
    }
});
router.post("/auth/password/reset", publicLimiter, async (req, res) => {
    try {
        const token = String(req.body?.token ?? "").trim();
        const password = String(req.body?.password ?? "").trim();
        if (!token || !password) {
            return res.status(400).json({
                error: { code: "TOKEN_AND_PASSWORD_REQUIRED", message: "Token and password are required." },
            });
        }
        if (password.length < 10) {
            return res.status(400).json({
                error: {
                    code: "PASSWORD_TOO_SHORT",
                    message: "Password must be at least 10 characters.",
                },
            });
        }
        const result = await verification_service_1.verificationService.resetPassword(token, password);
        return res.json(result);
    }
    catch (error) {
        return res.status(400).json({
            error: {
                code: "PASSWORD_RESET_FAILED",
                message: error?.message ?? "Failed to reset password.",
            },
        });
    }
});
exports.default = router;
