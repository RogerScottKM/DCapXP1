"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapCreateKycCaseDto = mapCreateKycCaseDto;
exports.mapUploadKycDocumentDto = mapUploadKycDocumentDto;
exports.mapKycDecisionDto = mapKycDecisionDto;
const prisma_json_1 = require("../../lib/prisma-json");
function mapCreateKycCaseDto(userId, dto) {
    return {
        user: { connect: { id: userId } },
        status: "IN_PROGRESS",
        notes: dto.notes,
    };
}
function mapUploadKycDocumentDto(kycCaseId, dto) {
    return {
        kycCase: { connect: { id: kycCaseId } },
        docType: dto.docType,
        fileKey: dto.fileKey,
        fileName: dto.fileName,
        mimeType: dto.mimeType,
        metadata: (0, prisma_json_1.asJson)(dto.metadata),
    };
}
function mapKycDecisionDto(kycCaseId, reviewerUserId, dto) {
    return {
        kycCase: { connect: { id: kycCaseId } },
        decision: dto.decision,
        reasonCode: dto.reasonCode,
        notes: dto.notes,
        reviewerUserId,
    };
}
