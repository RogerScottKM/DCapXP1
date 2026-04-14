"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.auditPrivilegedRequest = auditPrivilegedRequest;
const security_audit_1 = require("../lib/service/security-audit");
function auditPrivilegedRequest(action, resourceType, resourceId, metadataBuilder) {
    return async function auditPrivilegedRequestMiddleware(req, res, next) {
        try {
            await (0, security_audit_1.recordSecurityAudit)({
                actorId: req.auth?.userId ?? null,
                action,
                resourceType: resourceType ?? null,
                resourceId: typeof resourceId === "function" ? resourceId(req) ?? null : resourceId ?? null,
                metadata: metadataBuilder?.(req),
                req,
            });
        }
        catch (error) {
            console.error("[security-audit] privileged request middleware error", error);
        }
        next();
    };
}
