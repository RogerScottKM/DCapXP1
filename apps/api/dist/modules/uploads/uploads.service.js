"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.uploadsService = void 0;
const db_1 = require("../../db");
const api_error_1 = require("../../lib/errors/api-error");
const upload_policy_1 = require("./upload-policy");
class UploadsService {
    async presignUpload(request, userId) {
        if (request.purpose !== "KYC_DOCUMENT") {
            throw new api_error_1.ApiError({ statusCode: 400, code: "UNSUPPORTED_UPLOAD_PURPOSE", message: "Unsupported upload purpose." });
        }
        if (!upload_policy_1.KYC_UPLOAD_POLICY.allowedMimeTypes.includes(request.mimeType)) {
            throw new api_error_1.ApiError({ statusCode: 400, code: "UPLOAD_MIME_NOT_ALLOWED", message: "Unsupported file type.", fieldErrors: { mimeType: "Unsupported MIME type." } });
        }
        if (request.sizeBytes > upload_policy_1.KYC_UPLOAD_POLICY.maxSizeBytes) {
            throw new api_error_1.ApiError({ statusCode: 400, code: "UPLOAD_TOO_LARGE", message: "File exceeds size limit.", fieldErrors: { sizeBytes: "File too large." } });
        }
        const fileKey = `kyc/${userId}/${Date.now()}-${request.fileName}`;
        const uploadUrl = `https://storage.example.com/${fileKey}`; // ← replace with real S3/DO Spaces presign later
        return {
            fileKey,
            uploadUrl,
            expiresAtUtc: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
            headers: { "Content-Type": request.mimeType },
            constraints: upload_policy_1.KYC_UPLOAD_POLICY,
        };
    }
    async completeKycUpload(request, userId) {
        const kycCase = await db_1.prisma.kycCase.findFirst({ where: { id: request.kycCaseId, userId } });
        if (!kycCase) {
            throw new api_error_1.ApiError({ statusCode: 404, code: "KYC_CASE_NOT_FOUND", message: "KYC case not found." });
        }
        const document = await db_1.prisma.kycDocument.create({
            data: {
                kycCaseId: request.kycCaseId,
                docType: request.documentType,
                fileKey: request.fileKey,
                fileName: request.originalFileName,
                mimeType: request.mimeType,
                sizeBytes: request.sizeBytes,
                uploadStatus: "UPLOADED",
            },
        });
        return {
            documentId: document.id,
            kycCaseId: document.kycCaseId,
            uploadStatus: "UPLOADED",
        };
    }
}
exports.uploadsService = new UploadsService();
