"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const crypto_1 = __importDefault(require("crypto"));
const cors_1 = __importDefault(require("cors"));
const express_1 = __importDefault(require("express"));
const helmet_1 = __importDefault(require("helmet"));
const advisor_routes_1 = __importDefault(require("./modules/advisor/advisor.routes"));
const auth_routes_1 = __importDefault(require("./modules/auth/auth.routes"));
const consents_routes_1 = __importDefault(require("./modules/consents/consents.routes"));
const invitations_routes_1 = __importDefault(require("./modules/invitations/invitations.routes"));
const kyc_routes_1 = __importDefault(require("./modules/kyc/kyc.routes"));
const onboarding_routes_1 = __importDefault(require("./modules/onboarding/onboarding.routes"));
const referrals_routes_1 = __importDefault(require("./modules/referrals/referrals.routes"));
const uploads_routes_1 = __importDefault(require("./modules/uploads/uploads.routes"));
const verification_routes_1 = __importDefault(require("./modules/verification/verification.routes"));
const admin_1 = __importDefault(require("./routes/admin"));
const agentic_1 = __importDefault(require("./routes/agentic"));
const agents_1 = __importDefault(require("./routes/agents"));
const mandates_1 = __importDefault(require("./routes/mandates"));
const market_1 = __importDefault(require("./routes/market"));
const stream_1 = __importDefault(require("./routes/stream"));
const trade_1 = __importDefault(require("./routes/trade"));
const reconciliation_1 = __importDefault(require("./routes/reconciliation"));
const matching_events_1 = __importDefault(require("./routes/matching-events"));
const runtime_status_1 = __importDefault(require("./routes/runtime-status"));
const admin_health_1 = __importDefault(require("./routes/admin-health"));
const orders_1 = __importDefault(require("./routes/orders"));
const app = (0, express_1.default)();
const corsOrigins = (process.env.APP_CORS_ORIGINS ?? "http://localhost:3000")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
const apiRouters = [
    onboarding_routes_1.default,
    advisor_routes_1.default,
    consents_routes_1.default,
    uploads_routes_1.default,
    invitations_routes_1.default,
    auth_routes_1.default,
    verification_routes_1.default,
    kyc_routes_1.default,
    referrals_routes_1.default,
];
const trustProxy = process.env.TRUST_PROXY;
app.set("trust proxy", trustProxy === "1" || trustProxy === "true");
app.disable("x-powered-by");
app.set("json replacer", (_key, value) => {
    return typeof value === "bigint" ? value.toString() : value;
});
app.use((req, res, next) => {
    const requestId = req.header("x-request-id")?.trim() || crypto_1.default.randomUUID();
    req.requestId = requestId;
    res.setHeader("x-request-id", requestId);
    next();
});
app.use((0, helmet_1.default)({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
}));
app.use((_, res, next) => {
    res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
    next();
});
app.use((0, cors_1.default)({
    origin(origin, callback) {
        if (!origin || corsOrigins.includes(origin)) {
            return callback(null, true);
        }
        return callback(new Error("Origin not allowed by CORS"));
    },
    credentials: true,
}));
app.use(express_1.default.json({ limit: "100kb" }));
app.use(express_1.default.urlencoded({ extended: false, limit: "50kb" }));
app.get("/health", (_req, res) => {
    res.json({ ok: true });
});
app.get("/ready", (_req, res) => {
    res.json({ ok: true });
});
for (const prefix of ["/api", "/backend-api"]) {
    for (const router of apiRouters) {
        app.use(prefix, router);
    }
}
for (const prefix of ["/api/admin", "/admin"]) {
    app.use(prefix, admin_1.default);
}
for (const prefix of ["/api/v1/agents", "/v1/agents"]) {
    app.use(prefix, agents_1.default);
}
for (const prefix of ["/api/v1/mandates", "/v1/mandates"]) {
    app.use(prefix, mandates_1.default);
}
for (const prefix of ["/api/v1/ui", "/v1/ui"]) {
    app.use(prefix, agentic_1.default);
}
for (const prefix of ["", "/v1/market", "/api/v1/market"]) {
    app.use(prefix, market_1.default);
}
for (const prefix of ["", "/v1/trade", "/api/v1/trade"]) {
    app.use(prefix, trade_1.default);
}
for (const prefix of ["", "/v1/stream", "/api/v1/stream"]) {
    app.use(prefix, stream_1.default);
}
for (const prefix of ["/api/orders"]) {
    app.use(prefix, orders_1.default);
}
for (const prefix of ["/api/admin/reconciliation"]) {
    app.use(prefix, reconciliation_1.default);
}
app.use((req, res) => {
    const requestId = req.requestId;
    res.status(404).json({
        error: {
            code: "NOT_FOUND",
            message: "Route not found.",
        },
        requestId,
    });
});
app.use((err, req, res, _next) => {
    const status = err.statusCode || 500;
    const requestId = req.requestId;
    if (status >= 500) {
        console.error("[api-error]", {
            requestId,
            status,
            code: err.code || "INTERNAL_ERROR",
            message: err.message,
            path: req.originalUrl,
            method: req.method,
        });
    }
    res.status(status).json({
        error: {
            code: err.code || "INTERNAL_ERROR",
            message: err.message || "Internal server error.",
            fieldErrors: err.fieldErrors,
            retryable: err.retryable,
        },
        requestId,
    });
});
// ── Matching events stream routes ──────────────────────────
app.use("/api/market/events", matching_events_1.default);
// ── Runtime status routes ─────────────────────────────────
app.use("/api/admin/runtime-status", runtime_status_1.default);
// ── Admin health routes ───────────────────────────────────
app.use("/api/admin/health", admin_health_1.default);
exports.default = app;
