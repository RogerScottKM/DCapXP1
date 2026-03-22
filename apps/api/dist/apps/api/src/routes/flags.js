"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// apps/api/src/routes/flags.ts
const express_1 = __importDefault(require("express"));
const zod_1 = require("zod");
const featureFlags_1 = require("../infra/featureFlags");
const adminKey_1 = require("../infra/adminKey");
const router = express_1.default.Router();
function requireAdmin(req, res, next) {
    if (!(0, adminKey_1.isAdmin)(req))
        return res.status(401).json({ ok: false, error: "admin key required" });
    next();
}
const levelSchema = zod_1.z
    .union([zod_1.z.literal(2), zod_1.z.literal(3), zod_1.z.literal("2"), zod_1.z.literal("3")])
    .transform((v) => (String(v) === "3" ? 3 : 2));
const patchSchema = zod_1.z.object({
    orderbookDefaultLevel: levelSchema.optional(),
    streamDefaultLevel: levelSchema.optional(),
    publicAllowL3: zod_1.z.boolean().optional(),
    enableSSE: zod_1.z.boolean().optional(),
    reason: zod_1.z.string().optional(),
    updatedBy: zod_1.z.string().optional(),
}).strict();
router.get("/flags/defaults", requireAdmin, (_req, res) => {
    res.json({ ok: true, defaults: featureFlags_1.featureFlags.getDefaults() });
});
router.post("/flags/defaults", requireAdmin, (req, res) => {
    const patch = patchSchema.parse(req.body ?? {});
    const next = featureFlags_1.featureFlags.setDefaults(patch);
    res.json({ ok: true, defaults: next });
});
router.get("/flags/:symbol", requireAdmin, (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    if (!symbol)
        return res.status(400).json({ ok: false, error: "symbol required" });
    res.json({ ok: true, symbol, flags: featureFlags_1.featureFlags.get(symbol) });
});
router.post("/flags/:symbol", requireAdmin, (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    if (!symbol)
        return res.status(400).json({ ok: false, error: "symbol required" });
    const patch = patchSchema.parse(req.body ?? {});
    const next = featureFlags_1.featureFlags.set(symbol, patch);
    res.json({ ok: true, symbol, flags: next });
});
exports.default = router;
