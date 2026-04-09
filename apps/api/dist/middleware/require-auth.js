"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuth = requireAuth;
const api_error_1 = require("../lib/errors/api-error");
const auth_service_1 = require("../modules/auth/auth.service");
async function requireAuth(req, _res, next) {
    try {
        const auth = await auth_service_1.authService.resolveAuthFromRequest(req);
        if (!auth) {
            throw new api_error_1.ApiError({
                statusCode: 401,
                code: "UNAUTHENTICATED",
                message: "Authentication required.",
            });
        }
        req.auth = auth;
        next();
    }
    catch (error) {
        next(error);
    }
}
