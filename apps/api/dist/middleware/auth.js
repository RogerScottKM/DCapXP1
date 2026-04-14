"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAdminMfa = exports.requireMfa = void 0;
exports.requireUser = requireUser;
exports.authFromJwt = authFromJwt;
const api_error_1 = require("../lib/errors/api-error");
const require_auth_1 = require("./require-auth");
async function requireUser(req, res, next) {
    try {
        await new Promise((resolve, reject) => {
            void (0, require_auth_1.requireAuth)(req, res, (error) => {
                if (error) {
                    reject(error);
                    return;
                }
                resolve();
            });
        });
        if (!req.auth) {
            throw new api_error_1.ApiError({
                statusCode: 401,
                code: "UNAUTHENTICATED",
                message: "Authentication required.",
            });
        }
        req.user = {
            id: req.auth.userId,
            username: req.auth.userId,
        };
        next();
    }
    catch (error) {
        next(error);
    }
}
exports.requireMfa = (0, require_auth_1.requireRecentMfa)();
exports.requireAdminMfa = (0, require_auth_1.requireAdminRecentMfa)();
function authFromJwt(_req, _res, next) {
    next(new api_error_1.ApiError({
        statusCode: 501,
        code: "LEGACY_AUTH_DISABLED",
        message: "Legacy auth middleware is disabled. Use the canonical session-based require-auth middleware instead.",
    }));
}
