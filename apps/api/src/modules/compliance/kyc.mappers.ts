import { asJson } from "../../lib/prisma-json";
import { Prisma } from "@prisma/client";
import {
  CreateKycCaseDto,
  UploadKycDocumentDto,
  AdminKycCaseDecisionDto,
} from "./kyc.dto";

export function mapCreateKycCaseDto(userId: string, dto: CreateKycCaseDto): Prisma.KycCaseCreateInput {
  return {
    user: { connect: { id: userId } },
    status: "IN_PROGRESS",
    notes: dto.notes,
  };
}

export function mapUploadKycDocumentDto(
  kycCaseId: string,
  dto: UploadKycDocumentDto,
): Prisma.KycDocumentCreateInput {
  return {
    kycCase: { connect: { id: kycCaseId } },
    docType: dto.docType,
    fileKey: dto.fileKey,
    fileName: dto.fileName,
    mimeType: dto.mimeType,
    metadata: asJson(dto.metadata),
  };
}

export function mapKycDecisionDto(
  kycCaseId: string,
  reviewerUserId: string,
  dto: AdminKycCaseDecisionDto,
): Prisma.KycDecisionCreateInput {
  return {
    kycCase: { connect: { id: kycCaseId } },
    decision: dto.decision,
    reasonCode: dto.reasonCode,
    notes: dto.notes,
    reviewerUserId,
  };
}
