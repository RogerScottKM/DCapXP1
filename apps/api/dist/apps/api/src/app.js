"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const kyc_routes_1 = __importDefault(require("./modules/kyc/kyc.routes"));
const auth_routes_1 = __importDefault(require("./modules/auth/auth.routes"));
const onboarding_routes_1 = __importDefault(require("./modules/onboarding/onboarding.routes"));
const advisor_routes_1 = __importDefault(require("./modules/advisor/advisor.routes"));
// import invitationsRoutes from "./modules/invitations/invitations.routes";
const uploads_routes_1 = __importDefault(require("./modules/uploads/uploads.routes"));
const consents_routes_1 = __importDefault(require("./modules/consents/consents.routes"));
const app = (0, express_1.default)();
app.use((0, cors_1.default)({
    origin: [
        "http://localhost:3002",
        "http://localhost:53002",
    ],
    credentials: true,
}));
app.use(express_1.default.json());
// health check
app.get("/health", (_req, res) => {
    res.json({ ok: true });
});
// mount feature routes
app.use(onboarding_routes_1.default);
app.use(advisor_routes_1.default);
app.use(consents_routes_1.default);
app.use(uploads_routes_1.default);
// app.use(invitationsRoutes);
// Everything under /api so frontend calls match
app.use("/api", onboarding_routes_1.default);
app.use("/api", advisor_routes_1.default);
// app.use("/api", invitationsRoutes);
app.use("/api", uploads_routes_1.default);
app.use("/api", consents_routes_1.default);
app.use("/api", auth_routes_1.default);
app.use("/api", kyc_routes_1.default);
// Global error handler (uses our ApiError)
app.use((err, req, res, next) => {
    const status = err.statusCode || 500;
    res.status(status).json({
        error: {
            code: err.code || "INTERNAL_ERROR",
            message: err.message,
            fieldErrors: err.fieldErrors,
            retryable: err.retryable,
        },
    });
});
exports.default = app;
