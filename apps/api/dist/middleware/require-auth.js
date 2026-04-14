"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuth = requireAuth;
exports.requireRole = requireRole;
exports.requireRecentMfa = requireRecentMfa;
exports.requireAdminRecentMfa = requireAdminRecentMfa;
exports.requireLiveModeEligible = requireLiveModeEligible;
const api_error_1 = require("../lib/errors/api-error");
const prisma_1 = require("../lib/prisma");
const security_audit_1 = require("../lib/service/security-audit");
const auth_service_1 = require("../modules/auth/auth.service");
async function buildAuthContext(req) {
    const auth = await auth_service_1.authService.resolveAuthFromRequest(req);
    if (!auth) {
        return null;
    }
    const roles = await prisma_1.prisma.roleAssignment.findMany({
        where: { userId: auth.userId },
        select: { roleCode: true },
    });
    return {
        userId: auth.userId,
        sessionId: auth.sessionId,
        roleCodes: roles.map((role) => role.roleCode),
        mfaSatisfied: Boolean(auth.mfaVerifiedAt),
        mfaMethod: auth.mfaMethod ?? null,
        mfaVerifiedAt: auth.mfaVerifiedAt ?? null,
    };
}
async function auditAuthDecision(req, auth, action, metadata = {}) {
    await (0, security_audit_1.recordSecurityAudit)({
        actorType: auth?.userId ? "USER" : "ANONYMOUS",
        actorId: auth?.userId ?? null,
        action,
        resourceType: "ROUTE",
        resourceId: req.originalUrl || req.path || null,
        req,
        metadata: {
            method: req.method,
            path: req.originalUrl || req.path,
            ...metadata,
        },
    });
}
async function ensureAuthContext(req, res) {
    if (!req.auth) {
        await new Promise((resolve, reject) => {
            void requireAuth(req, res, (error) => {
                if (error) {
                    reject(error);
                    return;
                }
                resolve();
            });
        });
    }
    if (!req.auth) {
        throw new api_error_1.ApiError({
            statusCode: 401,
            code: "UNAUTHENTICATED",
            message: "Authentication required.",
        });
    }
    return req.auth;
}
function getMfaAgeMs(auth) {
    const verifiedAt = auth.mfaVerifiedAt ? new Date(auth.mfaVerifiedAt).getTime() : 0;
    return verifiedAt ? Date.now() - verifiedAt : Number.POSITIVE_INFINITY;
}
function isRecentMfa(auth, maxAgeSeconds) {
    const ageMs = getMfaAgeMs(auth);
    return Number.isFinite(ageMs) && ageMs <= maxAgeSeconds * 1000;
}
function getRequestedMode(req) {
    const bodyMode = typeof req.body?.mode === "string" ? req.body.mode : undefined;
    const queryMode = typeof req.query?.mode === "string"
        ? req.query.mode
        : Array.isArray(req.query?.mode)
            ? req.query.mode[0]
            : undefined;
    const headerMode = typeof req.headers["x-mode"] === "string" ? req.headers["x-mode"] : undefined;
    const mode = bodyMode ?? queryMode ?? headerMode;
    return mode ? String(mode).trim().toUpperCase() : undefined;
}
async function hasApprovedLiveEligibility(userId) {
    const approvedKycCase = await prisma_1.prisma.kycCase.findFirst({
        where: {
            userId,
            status: "APPROVED",
        },
        select: { id: true },
        orderBy: { updatedAt: "desc" },
    });
    if (approvedKycCase) {
        return true;
    }
    const legacyKycDelegate = prisma_1.prisma.kyc;
    if (legacyKycDelegate?.findFirst) {
        const approvedLegacyKyc = await legacyKycDelegate.findFirst({
            where: {
                userId,
                status: "APPROVED",
            },
            select: { id: true },
            orderBy: { updatedAt: "desc" },
        });
        if (approvedLegacyKyc) {
            return true;
        }
    }
    return false;
}
async function requireAuth(req, _res, next) {
    try {
        const auth = await buildAuthContext(req);
        if (!auth) {
            await auditAuthDecision(req, null, "AUTHZ_UNAUTHENTICATED_DENIED", {
                reason: "AUTH_REQUIRED",
            });
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
function requireRole(...allowedRoleCodes) {
    const allowed = new Set(allowedRoleCodes);
    return async function requireRoleMiddleware(req, res, next) {
        try {
            const auth = await ensureAuthContext(req, res);
            const hasRole = auth.roleCodes.some((roleCode) => allowed.has(roleCode));
            if (!hasRole) {
                await auditAuthDecision(req, auth, "AUTHZ_ROLE_DENIED", {
                    allowedRoleCodes,
                    currentRoleCodes: auth.roleCodes,
                });
                throw new api_error_1.ApiError({
                    statusCode: 403,
                    code: "FORBIDDEN",
                    message: "You do not have permission to perform this action.",
                });
            }
            next();
        }
        catch (error) {
            next(error);
        }
    };
}
function requireRecentMfa(maxAgeSeconds = 15 * 60) {
    return async function requireRecentMfaMiddleware(req, res, next) {
        try {
            const auth = await ensureAuthContext(req, res);
            const fresh = isRecentMfa(auth, maxAgeSeconds);
            req.auth = {
                ...auth,
                mfaSatisfied: fresh,
            };
            if (!fresh) {
                await auditAuthDecision(req, auth, "AUTHZ_MFA_REQUIRED_DENIED", {
                    maxAgeSeconds,
                    mfaMethod: auth.mfaMethod ?? null,
                    mfaVerifiedAt: auth.mfaVerifiedAt?.toISOString?.() ?? auth.mfaVerifiedAt ?? null,
                });
                throw new api_error_1.ApiError({
                    statusCode: 401,
                    code: "MFA_REQUIRED",
                    message: "A recent MFA challenge is required for this action.",
                    retryable: true,
                });
            }
            next();
        }
        catch (error) {
            next(error);
        }
    };
}
function requireAdminRecentMfa(allowedRoleCodes = ["ADMIN", "AUDITOR"], maxAgeSeconds = 15 * 60) {
    return async function requireAdminRecentMfaMiddleware(req, res, next) {
        try {
            const auth = await ensureAuthContext(req, res);
            const allowed = new Set(allowedRoleCodes);
            const hasRole = auth.roleCodes.some((roleCode) => allowed.has(roleCode));
            if (!hasRole) {
                await auditAuthDecision(req, auth, "AUTHZ_ADMIN_ROLE_DENIED", {
                    allowedRoleCodes,
                    currentRoleCodes: auth.roleCodes,
                });
                throw new api_error_1.ApiError({
                    statusCode: 403,
                    code: "FORBIDDEN",
                    message: "Administrator or auditor access is required.",
                });
            }
            const fresh = isRecentMfa(auth, maxAgeSeconds);
            req.auth = {
                ...auth,
                mfaSatisfied: fresh,
            };
            if (!fresh) {
                await auditAuthDecision(req, auth, "AUTHZ_ADMIN_MFA_REQUIRED_DENIED", {
                    maxAgeSeconds,
                    mfaMethod: auth.mfaMethod ?? null,
                    mfaVerifiedAt: auth.mfaVerifiedAt?.toISOString?.() ?? auth.mfaVerifiedAt ?? null,
                });
                throw new api_error_1.ApiError({
                    statusCode: 401,
                    code: "MFA_REQUIRED",
                    message: "A recent MFA challenge is required for administrative access.",
                    retryable: true,
                });
            }
            next();
        }
        catch (error) {
            next(error);
        }
    };
}
function requireLiveModeEligible(maxAgeSeconds = 15 * 60) {
    return async function requireLiveModeEligibleMiddleware(req, res, next) {
        try {
            const requestedMode = getRequestedMode(req);
            if (requestedMode !== "LIVE") {
                return next();
            }
            const auth = await ensureAuthContext(req, res);
            const fresh = isRecentMfa(auth, maxAgeSeconds);
            req.auth = {
                ...auth,
                mfaSatisfied: fresh,
            };
            if (!fresh) {
                await auditAuthDecision(req, auth, "AUTHZ_LIVE_MFA_REQUIRED_DENIED", {
                    requestedMode,
                    maxAgeSeconds,
                    mfaMethod: auth.mfaMethod ?? null,
                    mfaVerifiedAt: auth.mfaVerifiedAt?.toISOString?.() ?? auth.mfaVerifiedAt ?? null,
                });
                throw new api_error_1.ApiError({
                    statusCode: 401,
                    code: "MFA_REQUIRED",
                    message: "A recent MFA challenge is required for LIVE mode.",
                    retryable: true,
                });
            }
            const liveEligible = await hasApprovedLiveEligibility(auth.userId);
            if (!liveEligible) {
                await auditAuthDecision(req, auth, "LIVE_MODE_DENIED", {
                    requestedMode,
                    reason: "APPROVED_KYC_REQUIRED",
                });
                throw new api_error_1.ApiError({
                    statusCode: 403,
                    code: "LIVE_MODE_NOT_ALLOWED",
                    message: "Approved KYC is required for LIVE mode.",
                });
            }
            next();
        }
        catch (error) {
            next(error);
        }
    };
}
