"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const crypto_1 = __importDefault(require("crypto"));
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const kyc_routes_1 = __importDefault(require("./modules/kyc/kyc.routes"));
const auth_routes_1 = __importDefault(require("./modules/auth/auth.routes"));
const onboarding_routes_1 = __importDefault(require("./modules/onboarding/onboarding.routes"));
const advisor_routes_1 = __importDefault(require("./modules/advisor/advisor.routes"));
const invitations_routes_1 = __importDefault(require("./modules/invitations/invitations.routes"));
const uploads_routes_1 = __importDefault(require("./modules/uploads/uploads.routes"));
const consents_routes_1 = __importDefault(require("./modules/consents/consents.routes"));
const referrals_routes_1 = __importDefault(require("./modules/referrals/referrals.routes"));
const market_1 = __importDefault(require("./routes/market"));
const trade_1 = __importDefault(require("./routes/trade"));
const stream_1 = __importDefault(require("./routes/stream"));
const verification_routes_1 = __importDefault(require("./modules/verification/verification.routes"));
const app = (0, express_1.default)();
const corsOrigins = (process.env.APP_CORS_ORIGINS ?? "http://localhost:3002,http://localhost:53002")
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
app.set("trust proxy", process.env.TRUST_PROXY === "1");
app.set("json replacer", (_key, value) => {
    return typeof value === "bigint" ? value.toString() : value;
});
app.use((req, res, next) => {
    const requestId = req.header("x-request-id")?.trim() || crypto_1.default.randomUUID();
    req.requestId = requestId;
    res.setHeader("x-request-id", requestId);
    next();
});
app.use((_, res, next) => {
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("X-Frame-Options", "DENY");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=() ");
    next();
});
app.use((0, cors_1.default)({
    origin: corsOrigins,
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
for (const router of apiRouters) {
    app.use("/api", router);
    app.use("/backend-api", router);
}
app.use(market_1.default);
app.use(trade_1.default);
app.use(stream_1.default);
app.use("/v1/market", market_1.default);
app.use("/api/v1/market", market_1.default);
app.use("/v1/stream", stream_1.default);
app.use("/api/v1/stream", stream_1.default);
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
exports.default = app;
