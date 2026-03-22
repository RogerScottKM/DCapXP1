"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const onboarding_routes_1 = __importDefault(require("./modules/onboarding/onboarding.routes"));
const advisor_routes_1 = __importDefault(require("./modules/advisor/advisor.routes"));
const invitations_routes_1 = __importDefault(require("./modules/invitations/invitations.routes"));
const uploads_routes_1 = __importDefault(require("./modules/uploads/uploads.routes"));
const consents_routes_1 = __importDefault(require("./modules/consents/consents.routes"));
const app = (0, express_1.default)();
app.use(express_1.default.json());
// Everything under /api so frontend calls match
app.use("/api", onboarding_routes_1.default);
app.use("/api", advisor_routes_1.default);
app.use("/api", invitations_routes_1.default);
app.use("/api", uploads_routes_1.default);
app.use("/api", consents_routes_1.default);
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
