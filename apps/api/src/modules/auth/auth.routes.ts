import { Router } from "express";
import { getSession, login, logout, register } from "./auth.controller";
import { requireAuth } from "../../middleware/require-auth";

const router = Router();

router.post("/auth/register", register);
router.post("/auth/login", login);
router.get("/auth/session", getSession);
router.post("/auth/logout", requireAuth, logout);

export default router;
