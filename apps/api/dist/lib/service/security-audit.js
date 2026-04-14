"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.recordSecurityAudit = recordSecurityAudit;
const prisma_1 = require("../prisma");
function extractIp(input) {
    if (input.ipAddress?.trim()) {
        return input.ipAddress.trim();
    }
    const forwarded = input.req?.headers?.["x-forwarded-for"];
    if (typeof forwarded === "string" && forwarded.trim()) {
        return forwarded.split(",")[0].trim();
    }
    if (Array.isArray(forwarded) && forwarded.length > 0 && forwarded[0]?.trim()) {
        return forwarded[0].split(",")[0].trim();
    }
    const reqIp = input.req?.ip?.trim();
    if (reqIp) {
        return reqIp;
    }
    return input.req?.socket?.remoteAddress?.trim() ?? null;
}
function extractUserAgent(input) {
    if (input.userAgent?.trim()) {
        return input.userAgent.trim();
    }
    const header = input.req?.headers?.["user-agent"];
    if (typeof header === "string" && header.trim()) {
        return header.trim();
    }
    if (Array.isArray(header) && header.length > 0 && header[0]?.trim()) {
        return header[0].trim();
    }
    return null;
}
async function recordSecurityAudit(input) {
    try {
        await prisma_1.prisma.auditEvent.create({
            data: {
                actorType: input.actorType ?? (input.actorId ? "USER" : "SYSTEM"),
                actorId: input.actorId ?? null,
                subjectType: input.subjectType ?? null,
                subjectId: input.subjectId ?? null,
                action: input.action,
                resourceType: input.resourceType ?? null,
                resourceId: input.resourceId ?? null,
                ipAddress: extractIp(input),
                userAgent: extractUserAgent(input),
                metadata: input.metadata === undefined ? undefined : input.metadata,
            },
        });
    }
    catch (error) {
        console.error("[security-audit] failed to persist audit event", {
            action: input.action,
            actorId: input.actorId ?? null,
            resourceType: input.resourceType ?? null,
            resourceId: input.resourceId ?? null,
            error,
        });
    }
}
