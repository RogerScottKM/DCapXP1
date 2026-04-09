import { Router } from "express";
import {
  getSession,
  login,
  logout,
  register,
  requestPasswordReset,
  resetPassword,
  sendOtp,
  verifyOtp,
} from "./auth.controller";
import { requireAuth } from "../../middleware/require-auth";

const router = Router();

router.post("/auth/register", register);
router.post("/auth/login", login);
router.get("/auth/session", getSession);
router.post("/auth/logout", requireAuth, logout);

router.post("/auth/request-password-reset", requestPasswordReset);
router.post("/auth/reset-password", resetPassword);

router.post("/auth/send-otp", requireAuth, sendOtp);
router.post("/auth/verify-otp", requireAuth, verifyOtp);

export default router;
