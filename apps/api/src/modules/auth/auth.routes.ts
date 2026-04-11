import { Router } from "express";

import {
  activateTotp,
  challengeRecoveryCode,
  challengeTotp,
  enrollTotp,
  getSession,
  login,
  logout,
  regenerateRecoveryCodes,
  register,
  requestPasswordReset,
  resetPassword,
  sendOtp,
  verifyOtp,
} from "./auth.controller";
import { requireAuth, requireRecentMfa } from "../../middleware/require-auth";
import { simpleRateLimit } from "../../middleware/simple-rate-limit";

const router = Router();

const registerLimiter = simpleRateLimit({ keyPrefix: "auth:register", windowMs: 10 * 60 * 1000, max: 10 });
const loginLimiter = simpleRateLimit({ keyPrefix: "auth:login", windowMs: 10 * 60 * 1000, max: 20 });
const passwordLimiter = simpleRateLimit({ keyPrefix: "auth:password", windowMs: 10 * 60 * 1000, max: 10 });
const otpLimiter = simpleRateLimit({ keyPrefix: "auth:otp", windowMs: 10 * 60 * 1000, max: 10 });
const mfaLimiter = simpleRateLimit({ keyPrefix: "auth:mfa", windowMs: 10 * 60 * 1000, max: 20 });

router.post("/auth/register", registerLimiter, register);
router.post("/auth/login", loginLimiter, login);
router.get("/auth/session", getSession);
router.post("/auth/logout", requireAuth, logout);
router.post("/auth/request-password-reset", passwordLimiter, requestPasswordReset);
router.post("/auth/reset-password", passwordLimiter, resetPassword);
router.post("/auth/send-otp", requireAuth, otpLimiter, sendOtp);
router.post("/auth/verify-otp", requireAuth, otpLimiter, verifyOtp);

router.post("/auth/mfa/totp/enroll", requireAuth, mfaLimiter, enrollTotp);
router.post("/auth/mfa/totp/activate", requireAuth, mfaLimiter, activateTotp);
router.post("/auth/mfa/totp/challenge", requireAuth, mfaLimiter, challengeTotp);

router.post(
  "/auth/mfa/recovery-codes/regenerate",
  requireAuth,
  requireRecentMfa(),
  mfaLimiter,
  regenerateRecoveryCodes,
);
router.post(
  "/auth/mfa/recovery-codes/challenge",
  requireAuth,
  mfaLimiter,
  challengeRecoveryCode,
);

export default router;
