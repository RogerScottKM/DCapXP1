"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireUser = requireUser;
exports.requireMfa = requireMfa;
exports.authFromJwt = authFromJwt;
const api_error_1 = require("../lib/errors/api-error");
const auth_service_1 = require("../modules/auth/auth.service");
async function requireUser(req, _res, next) {
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
        req.user = { id: auth.userId, username: auth.userId };
        next();
    }
    catch (error) {
        next(error);
    }
}
function requireMfa(_req, _res, next) {
    next(new api_error_1.ApiError({
        statusCode: 501,
        code: "MFA_NOT_IMPLEMENTED",
        message: "Legacy development MFA bypass has been disabled. Wire this route to real TOTP/session step-up before enabling it in production.",
    }));
}
function authFromJwt(_req, _res, next) {
    next(new api_error_1.ApiError({
        statusCode: 501,
        code: "LEGACY_AUTH_DISABLED",
        message: "Legacy auth middleware is disabled. Use the canonical session-based require-auth middleware instead.",
    }));
}
