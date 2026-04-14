"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const audit_privileged_1 = require("../../middleware/audit-privileged");
const require_auth_1 = require("../../middleware/require-auth");
const invitations_controller_1 = require("./invitations.controller");
const router = (0, express_1.Router)();
function requireAdvisorOrAdminRecentMfa(req, res, next) {
    const roleCodes = new Set(req.auth?.roleCodes ?? []);
    if (roleCodes.has("admin") || roleCodes.has("auditor")) {
        return (0, require_auth_1.requireAdminRecentMfa)()(req, res, next);
    }
    return (0, require_auth_1.requireRecentMfa)()(req, res, next);
}
router.post("/advisor/invitations", require_auth_1.requireAuth, (0, require_auth_1.requireRole)("advisor", "admin"), requireAdvisorOrAdminRecentMfa, (0, audit_privileged_1.auditPrivilegedRequest)("INVITATION_CREATE_REQUESTED", "INVITATION"), invitations_controller_1.createInvitation);
router.get("/invitations/:token", invitations_controller_1.getInvitationByToken);
router.post("/invitations/:token/accept", require_auth_1.requireAuth, invitations_controller_1.acceptInvitation);
exports.default = router;
