"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getAdminKey = getAdminKey;
exports.isAdmin = isAdmin;
function getAdminKey() {
    return process.env.ADMIN_KEY ?? "change-me-now-please";
}
function isAdmin(req) {
    const k = req.header("x-admin-key");
    return Boolean(k) && k === getAdminKey();
}
