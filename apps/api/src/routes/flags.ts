// apps/api/src/routes/flags.ts
import express from "express";
import { z } from "zod";
import { featureFlags, type BookLevel } from "../infra/featureFlags";
import { isAdmin } from "../infra/adminKey";

const router = express.Router();

function requireAdmin(req: express.Request, res: express.Response, next: express.NextFunction) {
  if (!isAdmin(req)) return res.status(401).json({ ok: false, error: "admin key required" });
  next();
}

const levelSchema = z
  .union([z.literal(2), z.literal(3), z.literal("2"), z.literal("3")])
  .transform((v) => (String(v) === "3" ? (3 as BookLevel) : (2 as BookLevel)));

const patchSchema = z.object({
  orderbookDefaultLevel: levelSchema.optional(),
  streamDefaultLevel: levelSchema.optional(),
  publicAllowL3: z.boolean().optional(),
  enableSSE: z.boolean().optional(),
  reason: z.string().optional(),
  updatedBy: z.string().optional(),
}).strict();

router.get("/flags/defaults", requireAdmin, (_req, res) => {
  res.json({ ok: true, defaults: featureFlags.getDefaults() });
});

router.post("/flags/defaults", requireAdmin, (req, res) => {
  const patch = patchSchema.parse(req.body ?? {});
  const next = featureFlags.setDefaults(patch);
  res.json({ ok: true, defaults: next });
});

router.get("/flags/:symbol", requireAdmin, (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  if (!symbol) return res.status(400).json({ ok: false, error: "symbol required" });
  res.json({ ok: true, symbol, flags: featureFlags.get(symbol) });
});

router.post("/flags/:symbol", requireAdmin, (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  if (!symbol) return res.status(400).json({ ok: false, error: "symbol required" });

  const patch = patchSchema.parse(req.body ?? {});
  const next = featureFlags.set(symbol, patch);

  res.json({ ok: true, symbol, flags: next });
});

export default router;
