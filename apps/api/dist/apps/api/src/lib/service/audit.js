"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.writeAuditEvent = writeAuditEvent;
const prisma_json_1 = require("../prisma-json");
async function writeAuditEvent(tx, input) {
    await tx.auditEvent.create({
        data: {
            actorType: input.actorType,
            actorId: input.actorId ?? null,
            subjectType: input.subjectType ?? null,
            subjectId: input.subjectId ?? null,
            action: input.action,
            resourceType: input.resourceType ?? null,
            resourceId: input.resourceId ?? null,
            ipAddress: input.ipAddress ?? null,
            userAgent: input.userAgent ?? null,
            metadata: (0, prisma_json_1.asJson)(input.metadata),
        },
    });
}
