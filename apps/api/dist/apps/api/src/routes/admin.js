"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// apps/api/src/routes/admin.ts
const express_1 = __importDefault(require("express"));
const zod_1 = require("zod");
const symbolControl_1 = require("../infra/symbolControl");
const riskLimits_1 = require("../infra/riskLimits");
const bus_1 = require("../infra/bus");
const featureFlags_1 = require("../infra/featureFlags");
const router = express_1.default.Router();
/**
 * Very simple admin auth:
 * - Set env ADMIN_KEY in api container
 * - Call endpoints with header: x-admin-key: <ADMIN_KEY>
 */
function normalizeRiskPayload(payload) {
    return {
        ...payload,
        maxOrderQty: payload.maxOrderQty === undefined ? undefined : String(payload.maxOrderQty),
        maxOrderNotional: payload.maxOrderNotional === undefined ? undefined : String(payload.maxOrderNotional),
    };
}
function requireAdmin(req, res, next) {
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
const setModeSchema = zod_1.z.object({
    mode: zod_1.z.enum(["OPEN", "HALT", "CANCEL_ONLY"]),
    reason: zod_1.z.string().optional(),
    updatedBy: zod_1.z.string().optional(),
});
router.get("/symbols", (_req, res) => {
    res.json({ ok: true, symbols: symbolControl_1.symbolControl.list() });
});
router.get("/symbols/:symbol", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    res.json({ ok: true, symbol, control: symbolControl_1.symbolControl.get(symbol) });
});
router.post("/symbols/:symbol", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    const payload = setModeSchema.parse(req.body);
    const control = symbolControl_1.symbolControl.set(symbol, {
        mode: payload.mode,
        reason: payload.reason,
        updatedBy: payload.updatedBy,
    });
    bus_1.bus.emit("symbolMode", { symbol });
    res.json({ ok: true, symbol, control });
});
router.post("/symbols/:symbol/clear", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    symbolControl_1.symbolControl.clear(symbol);
    bus_1.bus.emit("symbolMode", { symbol });
    res.json({ ok: true, symbol, control: symbolControl_1.symbolControl.get(symbol) });
});
// --------------------
// RISK LIMIT CONTROLS
// --------------------
const riskSchema = zod_1.z.object({
    maxOrderQty: zod_1.z.union([zod_1.z.string(), zod_1.z.number()]).optional(),
    maxOrderNotional: zod_1.z.union([zod_1.z.string(), zod_1.z.number()]).optional(),
    maxOpenOrders: zod_1.z.number().int().min(0).optional(),
    reason: zod_1.z.string().optional(),
    updatedBy: zod_1.z.string().optional(),
});
router.get("/risk/defaults", (_req, res) => {
    res.json({ ok: true, defaults: riskLimits_1.riskLimits.getDefaults() });
});
router.post("/risk/defaults", (req, res) => {
    const payload = riskSchema.parse(req.body);
    const defaults = riskLimits_1.riskLimits.setDefaults(normalizeRiskPayload(payload));
    // optional: broadcast a "*" marker
    bus_1.bus.emit("riskLimits", { symbol: "*" });
    res.json({ ok: true, defaults });
});
router.get("/risk", (_req, res) => {
    res.json({ ok: true, overrides: riskLimits_1.riskLimits.listOverrides() });
});
router.get("/risk/:symbol", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    res.json({ ok: true, symbol, limits: riskLimits_1.riskLimits.get(symbol) });
});
router.post("/risk/:symbol", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    const payload = riskSchema.parse(req.body);
    const limits = riskLimits_1.riskLimits.set(symbol, normalizeRiskPayload(payload));
    bus_1.bus.emit("riskLimits", { symbol });
    res.json({ ok: true, symbol, limits });
});
router.post("/risk/:symbol/clear", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    riskLimits_1.riskLimits.clear(symbol);
    bus_1.bus.emit("riskLimits", { symbol });
    res.json({ ok: true, symbol, limits: riskLimits_1.riskLimits.get(symbol) });
});
// --------------------
// FEATURE FLAGS CONTROLS
// --------------------
const flagsSchema = zod_1.z.object({
    orderbookDefaultLevel: zod_1.z.union([zod_1.z.literal(2), zod_1.z.literal(3)]).optional(),
    streamDefaultLevel: zod_1.z.union([zod_1.z.literal(2), zod_1.z.literal(3)]).optional(),
    publicAllowL3: zod_1.z.boolean().optional(),
    enableSSE: zod_1.z.boolean().optional(),
    reason: zod_1.z.string().optional(),
    updatedBy: zod_1.z.string().optional(),
});
router.get("/flags/defaults", (_req, res) => {
    res.json({ ok: true, defaults: featureFlags_1.featureFlags.getDefaults() });
});
router.post("/flags/defaults", (req, res) => {
    const payload = flagsSchema.parse(req.body);
    const defaults = featureFlags_1.featureFlags.setDefaults(payload);
    // Broadcast so connected UIs live-refresh without reload
    bus_1.bus.emit("flags", { symbol: "*" });
    res.json({ ok: true, defaults });
});
router.get("/flags", (_req, res) => {
    res.json({ ok: true, overrides: featureFlags_1.featureFlags.listOverrides() });
});
router.get("/flags/:symbol", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    res.json({ ok: true, symbol, flags: featureFlags_1.featureFlags.get(symbol) });
});
router.post("/flags/:symbol", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    const payload = flagsSchema.parse(req.body);
    const flags = featureFlags_1.featureFlags.set(symbol, payload);
    bus_1.bus.emit("flags", { symbol });
    res.json({ ok: true, symbol, flags });
});
router.post("/flags/:symbol/clear", (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    featureFlags_1.featureFlags.clear(symbol);
    bus_1.bus.emit("flags", { symbol });
    res.json({ ok: true, symbol, flags: featureFlags_1.featureFlags.get(symbol) });
});
exports.default = router;
