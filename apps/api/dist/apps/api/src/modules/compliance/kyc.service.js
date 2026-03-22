"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createKycCase = createKycCase;
exports.uploadKycDocument = uploadKycDocument;
exports.decideKycCase = decideKycCase;
const prisma_1 = require("../../lib/prisma");
const zod_1 = require("../../lib/service/zod");
const tx_1 = require("../../lib/service/tx");
const audit_1 = require("../../lib/service/audit");
const kyc_dto_1 = require("./kyc.dto");
const kyc_mappers_1 = require("./kyc.mappers");
async function createKycCase(userId, input) {
    const dto = (0, zod_1.parseDto)(kyc_dto_1.createKycCaseDto, input);
    return (0, tx_1.withTx)(prisma_1.prisma, async (tx) => {
        const kycCase = await tx.kycCase.create({
            data: (0, kyc_mappers_1.mapCreateKycCaseDto)(userId, dto),
        });
        await (0, audit_1.writeAuditEvent)(tx, {
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
async function uploadKycDocument(userId, kycCaseId, input) {
    const dto = (0, zod_1.parseDto)(kyc_dto_1.uploadKycDocumentDto, input);
    return (0, tx_1.withTx)(prisma_1.prisma, async (tx) => {
        const doc = await tx.kycDocument.create({
            data: (0, kyc_mappers_1.mapUploadKycDocumentDto)(kycCaseId, dto),
        });
        await (0, audit_1.writeAuditEvent)(tx, {
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
async function decideKycCase(reviewerUserId, kycCaseId, input) {
    const dto = (0, zod_1.parseDto)(kyc_dto_1.adminKycCaseDecisionDto, input);
    return (0, tx_1.withTx)(prisma_1.prisma, async (tx) => {
        const decision = await tx.kycDecision.create({
            data: (0, kyc_mappers_1.mapKycDecisionDto)(kycCaseId, reviewerUserId, dto),
        });
        const nextStatus = dto.decision === "APPROVE"
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
        await (0, audit_1.writeAuditEvent)(tx, {
            actorType: "USER",
            actorId: reviewerUserId,
            action: dto.decision === "APPROVE"
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
