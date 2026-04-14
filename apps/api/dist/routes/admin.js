"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const audit_privileged_1 = require("../middleware/audit-privileged");
const require_auth_1 = require("../middleware/require-auth");
const bus_1 = require("../infra/bus");
const featureFlags_1 = require("../infra/featureFlags");
const riskLimits_1 = require("../infra/riskLimits");
const symbolControl_1 = require("../infra/symbolControl");
const router = (0, express_1.Router)();
const requireAdminRole = (0, require_auth_1.requireRole)("admin", "auditor");
const requireAdminStepUp = (0, require_auth_1.requireAdminRecentMfa)(["admin", "auditor"]);
router.use(require_auth_1.requireAuth, requireAdminRole, requireAdminStepUp);
function normalizeRiskPayload(payload) {
    return {
        ...payload,
        maxOrderQty: payload.maxOrderQty === undefined ? undefined : String(payload.maxOrderQty),
        maxOrderNotional: payload.maxOrderNotional === undefined ? undefined : String(payload.maxOrderNotional),
    };
}
const setModeSchema = zod_1.z.object({
    mode: zod_1.z.enum(["OPEN", "HALT", "CANCEL_ONLY"]),
    reason: zod_1.z.string().optional(),
    updatedBy: zod_1.z.string().optional(),
});
const riskSchema = zod_1.z.object({
    maxOrderQty: zod_1.z.union([zod_1.z.string(), zod_1.z.number()]).optional(),
    maxOrderNotional: zod_1.z.union([zod_1.z.string(), zod_1.z.number()]).optional(),
    maxOpenOrders: zod_1.z.number().int().min(0).optional(),
    reason: zod_1.z.string().optional(),
    updatedBy: zod_1.z.string().optional(),
});
const flagsSchema = zod_1.z.object({
    orderbookDefaultLevel: zod_1.z.union([zod_1.z.literal(2), zod_1.z.literal(3)]).optional(),
    streamDefaultLevel: zod_1.z.union([zod_1.z.literal(2), zod_1.z.literal(3)]).optional(),
    publicAllowL3: zod_1.z.boolean().optional(),
    enableSSE: zod_1.z.boolean().optional(),
    reason: zod_1.z.string().optional(),
    updatedBy: zod_1.z.string().optional(),
});
function symbolFromReq(req) {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    return symbol || undefined;
}
router.get("/symbols", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_SYMBOLS_LIST", "SYMBOL"), (_req, res) => {
    res.json({ ok: true, symbols: symbolControl_1.symbolControl.list() });
});
router.get("/symbols/:symbol", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_SYMBOL_GET", "SYMBOL", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    res.json({ ok: true, symbol, control: symbolControl_1.symbolControl.get(symbol) });
});
router.post("/symbols/:symbol", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_SYMBOL_SET", "SYMBOL", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    const payload = setModeSchema.parse(req.body);
    const control = symbolControl_1.symbolControl.set(symbol, {
        mode: payload.mode,
        reason: payload.reason,
        updatedBy: payload.updatedBy ?? req.auth?.userId,
    });
    bus_1.bus.emit("symbolMode", { symbol });
    res.json({ ok: true, symbol, control });
});
router.post("/symbols/:symbol/clear", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_SYMBOL_CLEAR", "SYMBOL", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    symbolControl_1.symbolControl.clear(symbol);
    bus_1.bus.emit("symbolMode", { symbol });
    res.json({ ok: true, symbol, control: symbolControl_1.symbolControl.get(symbol) });
});
router.get("/risk/defaults", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_RISK_DEFAULTS_GET", "RISK_LIMIT"), (_req, res) => {
    res.json({ ok: true, defaults: riskLimits_1.riskLimits.getDefaults() });
});
router.post("/risk/defaults", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_RISK_DEFAULTS_SET", "RISK_LIMIT"), (req, res) => {
    const payload = riskSchema.parse(req.body);
    const defaults = riskLimits_1.riskLimits.setDefaults(normalizeRiskPayload(payload));
    bus_1.bus.emit("riskLimits", { symbol: "*" });
    res.json({ ok: true, defaults });
});
router.get("/risk", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_RISK_OVERRIDES_LIST", "RISK_LIMIT"), (_req, res) => {
    res.json({ ok: true, overrides: riskLimits_1.riskLimits.listOverrides() });
});
router.get("/risk/:symbol", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_RISK_GET", "RISK_LIMIT", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    res.json({ ok: true, symbol, limits: riskLimits_1.riskLimits.get(symbol) });
});
router.post("/risk/:symbol", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_RISK_SET", "RISK_LIMIT", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    const payload = riskSchema.parse(req.body);
    const limits = riskLimits_1.riskLimits.set(symbol, normalizeRiskPayload(payload));
    bus_1.bus.emit("riskLimits", { symbol });
    res.json({ ok: true, symbol, limits });
});
router.post("/risk/:symbol/clear", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_RISK_CLEAR", "RISK_LIMIT", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    riskLimits_1.riskLimits.clear(symbol);
    bus_1.bus.emit("riskLimits", { symbol });
    res.json({ ok: true, symbol, limits: riskLimits_1.riskLimits.get(symbol) });
});
router.get("/flags/defaults", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_FLAGS_DEFAULTS_GET", "FEATURE_FLAG"), (_req, res) => {
    res.json({ ok: true, defaults: featureFlags_1.featureFlags.getDefaults() });
});
router.post("/flags/defaults", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_FLAGS_DEFAULTS_SET", "FEATURE_FLAG"), (req, res) => {
    const payload = flagsSchema.parse(req.body);
    const defaults = featureFlags_1.featureFlags.setDefaults(payload);
    bus_1.bus.emit("flags", { symbol: "*" });
    res.json({ ok: true, defaults });
});
router.get("/flags", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_FLAGS_OVERRIDES_LIST", "FEATURE_FLAG"), (_req, res) => {
    res.json({ ok: true, overrides: featureFlags_1.featureFlags.listOverrides() });
});
router.get("/flags/:symbol", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_FLAGS_GET", "FEATURE_FLAG", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    res.json({ ok: true, symbol, flags: featureFlags_1.featureFlags.get(symbol) });
});
router.post("/flags/:symbol", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_FLAGS_SET", "FEATURE_FLAG", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    const payload = flagsSchema.parse(req.body);
    const flags = featureFlags_1.featureFlags.set(symbol, payload);
    bus_1.bus.emit("flags", { symbol });
    res.json({ ok: true, symbol, flags });
});
router.post("/flags/:symbol/clear", (0, audit_privileged_1.auditPrivilegedRequest)("ADMIN_FLAGS_CLEAR", "FEATURE_FLAG", (req) => symbolFromReq(req)), (req, res) => {
    const symbol = symbolFromReq(req);
    featureFlags_1.featureFlags.clear(symbol);
    bus_1.bus.emit("flags", { symbol });
    res.json({ ok: true, symbol, flags: featureFlags_1.featureFlags.get(symbol) });
});
exports.default = router;
