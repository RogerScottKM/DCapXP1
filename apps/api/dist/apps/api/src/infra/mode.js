"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveMode = resolveMode;
function resolveMode(req) {
    const raw = String(req.header("x-mode") ??
        req.query.mode ??
        req.body?.mode ??
        "PAPER");
    const m = raw.toUpperCase().trim();
    return m === "LIVE" ? "LIVE" : "PAPER";
}
