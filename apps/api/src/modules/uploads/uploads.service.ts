import type { CompleteKycUploadRequest, CompleteKycUploadResponse, PresignUploadRequest, PresignUploadResponse } from "@dcapx/contracts";
import { prisma } from "../../db";
import { ApiError } from "../../lib/errors/api-error";
import { KYC_UPLOAD_POLICY } from "./upload-policy";

class UploadsService {
  async presignUpload(request: PresignUploadRequest, userId: string): Promise<PresignUploadResponse> {
    if (request.purpose !== "KYC_DOCUMENT") {
      throw new ApiError({ statusCode: 400, code: "UNSUPPORTED_UPLOAD_PURPOSE", message: "Unsupported upload purpose." });
    }
    if (!KYC_UPLOAD_POLICY.allowedMimeTypes.includes(request.mimeType)) {
      throw new ApiError({ statusCode: 400, code: "UPLOAD_MIME_NOT_ALLOWED", message: "Unsupported file type.", fieldErrors: { mimeType: "Unsupported MIME type." } });
    }
    if (request.sizeBytes > KYC_UPLOAD_POLICY.maxSizeBytes) {
      throw new ApiError({ statusCode: 400, code: "UPLOAD_TOO_LARGE", message: "File exceeds size limit.", fieldErrors: { sizeBytes: "File too large." } });
    }
    const fileKey = `kyc/${userId}/${Date.now()}-${request.fileName}`;
    const uploadUrl = `https://storage.example.com/${fileKey}`; // ← replace with real S3/DO Spaces presign later
    return {
      fileKey,
      uploadUrl,
      expiresAtUtc: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      headers: { "Content-Type": request.mimeType },
      constraints: KYC_UPLOAD_POLICY,
    };
  }
  async completeKycUpload(request: CompleteKycUploadRequest, userId: string): Promise<CompleteKycUploadResponse> {
    const kycCase = await prisma.kycCase.findFirst({ where: { id: request.kycCaseId, userId } });
    if (!kycCase) {
      throw new ApiError({ statusCode: 404, code: "KYC_CASE_NOT_FOUND", message: "KYC case not found." });
    }
    const document = await prisma.kycDocument.create({
      data: {
        kycCaseId: request.kycCaseId,
  docType: request.documentType as any,
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
export const uploadsService = new UploadsService();
