// apps/api/src/routes/agentic.ts
import { Router } from "express";
import { generateUIPlan } from "../agentic/plan";

const router = Router();

/**
 * GET /plan
 * Mounted at:
 *  - /api/v1/ui  => /api/v1/ui/plan
 *  - /v1/ui      => /v1/ui/plan
 */
router.get("/plan", (req, res) => {
  const plan = generateUIPlan({
    userId: req.query.userId,
    intent: req.query.intent,
    symbol: req.query.symbol,
  });

  res.json(plan);
});

export default router;
