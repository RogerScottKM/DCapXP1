"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuth = requireAuth;
const api_error_1 = require("../lib/errors/api-error");
function requireAuth(req, res, next) {
    if (!req.auth?.userId) {
        throw new api_error_1.ApiError({
            statusCode: 401,
            code: "UNAUTHENTICATED",
            message: "Authentication required.",
        });
    }
    next();
}
