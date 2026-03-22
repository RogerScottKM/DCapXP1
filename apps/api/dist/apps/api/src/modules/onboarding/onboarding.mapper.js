"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.makeStep = makeStep;
exports.deriveOverallStatus = deriveOverallStatus;
exports.deriveCompletionPercent = deriveCompletionPercent;
function makeStep(code, label, status, required, completedAtUtc, details) { return { code, label, status, required, completedAtUtc, details }; }
function deriveOverallStatus(steps) { const required = steps.filter((s) => s.required); if (required.every((s) => s.status === "COMPLETED"))
    return "COMPLETED"; if (required.some((s) => s.status === "FAILED" || s.status === "BLOCKED"))
    return "ACTION_REQUIRED"; if (required.some((s) => s.status === "IN_PROGRESS"))
    return "PENDING_REVIEW"; return "IN_PROGRESS"; }
function deriveCompletionPercent(steps) { const required = steps.filter((s) => s.required); if (required.length === 0)
    return 0; const completed = required.filter((s) => s.status === "COMPLETED").length; return Math.round((completed / required.length) * 100); }
