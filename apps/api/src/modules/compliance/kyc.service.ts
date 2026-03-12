import { prisma } from "../../lib/prisma";
import { parseDto } from "../../lib/service/zod";
import { withTx } from "../../lib/service/tx";
import { writeAuditEvent } from "../../lib/service/audit";
import {
  createKycCaseDto,
  uploadKycDocumentDto,
  adminKycCaseDecisionDto,
} from "./kyc.dto";
import {
  mapCreateKycCaseDto,
  mapUploadKycDocumentDto,
  mapKycDecisionDto,
} from "./kyc.mappers";

export async function createKycCase(userId: string, input: unknown) {
  const dto = parseDto(createKycCaseDto, input);

  return withTx(prisma, async (tx) => {
    const kycCase = await tx.kycCase.create({
      data: mapCreateKycCaseDto(userId, dto),
    });

    await writeAuditEvent(tx, {
      actorType: "USER",
      actorId: userId,
      subjectType: "USER",
      subjectId: userId,
      action: "KYC_CASE_CREATED",
      resourceType: "KycCase",
      resourceId: kycCase.id,
    });

    return kycCase;
  });
}

export async function uploadKycDocument(userId: string, kycCaseId: string, input: unknown) {
  const dto = parseDto(uploadKycDocumentDto, input);

  return withTx(prisma, async (tx) => {
    const doc = await tx.kycDocument.create({
      data: mapUploadKycDocumentDto(kycCaseId, dto),
    });

    await writeAuditEvent(tx, {
      actorType: "USER",
      actorId: userId,
      subjectType: "USER",
      subjectId: userId,
      action: "KYC_DOCUMENT_UPLOADED",
      resourceType: "KycDocument",
      resourceId: doc.id,
      metadata: { kycCaseId, docType: dto.docType },
    });

    return doc;
  });
}

export async function decideKycCase(reviewerUserId: string, kycCaseId: string, input: unknown) {
  const dto = parseDto(adminKycCaseDecisionDto, input);

  return withTx(prisma, async (tx) => {
    const decision = await tx.kycDecision.create({
      data: mapKycDecisionDto(kycCaseId, reviewerUserId, dto),
    });

    const nextStatus =
      dto.decision === "APPROVE"
        ? "APPROVED"
        : dto.decision === "REJECT"
        ? "REJECTED"
        : "NEEDS_INFO";

    await tx.kycCase.update({
      where: { id: kycCaseId },
      data: {
        status: nextStatus,
        reviewerUserId,
        reviewedAt: new Date(),
      },
    });

    await writeAuditEvent(tx, {
      actorType: "USER",
      actorId: reviewerUserId,
      action:
        dto.decision === "APPROVE"
          ? "KYC_APPROVED"
          : dto.decision === "REJECT"
          ? "KYC_REJECTED"
          : "KYC_REQUESTED_INFO",
      resourceType: "KycCase",
      resourceId: kycCaseId,
      metadata: { decisionId: decision.id },
    });

    return decision;
  });
}

