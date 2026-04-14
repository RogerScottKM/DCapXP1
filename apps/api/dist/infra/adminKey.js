"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getAdminKey = getAdminKey;
exports.isAdmin = isAdmin;
const crypto_1 = __importDefault(require("crypto"));
function getAdminKey() {
    const value = process.env.ADMIN_KEY?.trim();
    if (!value) {
        throw new Error("ADMIN_KEY is required");
    }
    return value;
}
function readHeader(req, name) {
    if (typeof req.header === "function") {
        const value = req.header(name);
        return typeof value === "string" ? value : undefined;
    }
    const raw = req.headers?.[name.toLowerCase()];
    if (Array.isArray(raw)) {
        return typeof raw[0] === "string" ? raw[0] : undefined;
    }
    return typeof raw === "string" ? raw : undefined;
}
function timingSafeEqualString(a, b) {
    const aBuf = Buffer.from(a);
    const bBuf = Buffer.from(b);
    if (aBuf.length !== bBuf.length) {
        return false;
    }
    return crypto_1.default.timingSafeEqual(aBuf, bBuf);
}
/**
 * Backward-compatible helper for older admin-key protected routes.
 * Cleanup B will replace these routes with RBAC + MFA, but for now
 * we keep this named export so the old imports still compile.
 */
function isAdmin(req) {
    const provided = readHeader(req, "x-admin-key")?.trim();
    if (!provided) {
        return false;
    }
    const expected = getAdminKey();
    return timingSafeEqualString(provided, expected);
}
exports.default = getAdminKey;
