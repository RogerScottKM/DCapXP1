import { Tx } from "./tx";
import { asJson } from "../prisma-json";

type AuditInput = {
  actorType: string;
  actorId?: string | null;
  subjectType?: string | null;
  subjectId?: string | null;
  action: string;
  resourceType?: string | null;
  resourceId?: string | null;
  ipAddress?: string | null;
  userAgent?: string | null;
  metadata?: Record<string, unknown> | null;
};

export async function writeAuditEvent(tx: Tx, input: AuditInput) {
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
      metadata: asJson(input.metadata),
    },
  });
}
