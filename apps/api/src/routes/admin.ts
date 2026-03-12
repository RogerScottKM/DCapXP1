// apps/api/src/routes/admin.ts
import express from "express";
import { z } from "zod";
import { symbolControl, type TradingMode } from "../infra/symbolControl";
import { riskLimits } from "../infra/riskLimits";
import { bus } from "../infra/bus";
import { featureFlags } from "../infra/featureFlags";

const router = express.Router();

/**
 * Very simple admin auth:
 * - Set env ADMIN_KEY in api container
 * - Call endpoints with header: x-admin-key: <ADMIN_KEY>
 */

function normalizeRiskPayload(payload: {
  maxOrderQty?: string | number;
  maxOrderNotional?: string | number;
  maxOpenOrders?: number;
  reason?: string;
  updatedBy?: string;
}) {
  return {
    ...payload,
    maxOrderQty: payload.maxOrderQty === undefined ? undefined : String(payload.maxOrderQty),
    maxOrderNotional:
      payload.maxOrderNotional === undefined ? undefined : String(payload.maxOrderNotional),
  };
}

function requireAdmin(req: express.Request, res: express.Response, next: express.NextFunction) {
  const expected = process.env.ADMIN_KEY;
  if (!expected) {
    return res.status(500).json({
      ok: false,
      error: "ADMIN_KEY is not set on the API service",
    });
  }

  const got = String(req.header("x-admin-key") ?? "");
  if (got !== expected) {
    return res.status(403).json({ ok: false, error: "forbidden" });
  }

  return next();
}

router.use(requireAdmin);

// --------------------
// SYMBOL MODE CONTROLS
// --------------------
const setModeSchema = z.object({
  mode: z.enum(["OPEN", "HALT", "CANCEL_ONLY"]),
  reason: z.string().optional(),
  updatedBy: z.string().optional(),
});

router.get("/symbols", (_req, res) => {
  res.json({ ok: true, symbols: symbolControl.list() });
});

router.get("/symbols/:symbol", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  res.json({ ok: true, symbol, control: symbolControl.get(symbol) });
});

router.post("/symbols/:symbol", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  const payload = setModeSchema.parse(req.body);

  const control = symbolControl.set(symbol, {
    mode: payload.mode as TradingMode,
    reason: payload.reason,
    updatedBy: payload.updatedBy,
  });

  bus.emit("symbolMode", {symbol});

  res.json({ ok: true, symbol, control });
});

router.post("/symbols/:symbol/clear", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  symbolControl.clear(symbol);

  bus.emit("symbolMode", {symbol});

  res.json({ ok: true, symbol, control: symbolControl.get(symbol) });
});

// --------------------
// RISK LIMIT CONTROLS
// --------------------
const riskSchema = z.object({
  maxOrderQty: z.union([z.string(), z.number()]).optional(),
  maxOrderNotional: z.union([z.string(), z.number()]).optional(),
  maxOpenOrders: z.number().int().min(0).optional(),
  reason: z.string().optional(),
  updatedBy: z.string().optional(),
});

router.get("/risk/defaults", (_req, res) => {
  res.json({ ok: true, defaults: riskLimits.getDefaults() });
});

router.post("/risk/defaults", (req, res) => {
  const payload = riskSchema.parse(req.body);
  const defaults = riskLimits.setDefaults(normalizeRiskPayload(payload));

  // optional: broadcast a "*" marker
  bus.emit("riskLimits", { symbol: "*" });

  res.json({ ok: true, defaults });
});

router.get("/risk", (_req, res) => {
  res.json({ ok: true, overrides: riskLimits.listOverrides() });
});

router.get("/risk/:symbol", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  res.json({ ok: true, symbol, limits: riskLimits.get(symbol) });
});

router.post("/risk/:symbol", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  const payload = riskSchema.parse(req.body);

  const limits = riskLimits.set(symbol, normalizeRiskPayload(payload));

  bus.emit("riskLimits", {symbol});

  res.json({ ok: true, symbol, limits });
});

router.post("/risk/:symbol/clear", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  riskLimits.clear(symbol);

  bus.emit("riskLimits", {symbol});

  res.json({ ok: true, symbol, limits: riskLimits.get(symbol) });
});

// --------------------
// FEATURE FLAGS CONTROLS
// --------------------
const flagsSchema = z.object({
  orderbookDefaultLevel: z.union([z.literal(2), z.literal(3)]).optional(),
  streamDefaultLevel: z.union([z.literal(2), z.literal(3)]).optional(),
  publicAllowL3: z.boolean().optional(),
  enableSSE: z.boolean().optional(),
  reason: z.string().optional(),
  updatedBy: z.string().optional(),
});

router.get("/flags/defaults", (_req, res) => {
  res.json({ ok: true, defaults: featureFlags.getDefaults() });
});

router.post("/flags/defaults", (req, res) => {
  const payload = flagsSchema.parse(req.body);
  const defaults = featureFlags.setDefaults(payload);

  // Broadcast so connected UIs live-refresh without reload
  bus.emit("flags",{ symbol: "*" });

  res.json({ ok: true, defaults });
});

router.get("/flags", (_req, res) => {
  res.json({ ok: true, overrides: featureFlags.listOverrides() });
});

router.get("/flags/:symbol", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  res.json({ ok: true, symbol, flags: featureFlags.get(symbol) });
});

router.post("/flags/:symbol", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  const payload = flagsSchema.parse(req.body);

  const flags = featureFlags.set(symbol, payload);

  bus.emit("flags", {symbol});

  res.json({ ok: true, symbol, flags });
});

router.post("/flags/:symbol/clear", (req, res) => {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  featureFlags.clear(symbol);

  bus.emit("flags", {symbol});

  res.json({ ok: true, symbol, flags: featureFlags.get(symbol) });
});

export default router;
