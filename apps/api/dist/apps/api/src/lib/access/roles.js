"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.hasScopedRole = hasScopedRole;
function hasScopedRole(assignments, roleCode, scopeType, scopeId) { return assignments.some((a) => { if (a.roleCode !== roleCode)
    return false; if (a.scopeType !== scopeType)
    return false; if (scopeType === "GLOBAL")
    return true; return a.scopeId === (scopeId ?? null); }); }
