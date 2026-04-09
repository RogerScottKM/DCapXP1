import type { UtcIsoString } from "./common";
export type UploadPurpose = "KYC_DOCUMENT";
export interface PresignUploadRequest {
    purpose: UploadPurpose;
    fileName: string;
    mimeType: string;
    sizeBytes: number;
}
export interface PresignUploadResponse {
    fileKey: string;
    uploadUrl: string;
    expiresAtUtc: UtcIsoString;
    headers?: Record<string, string>;
    constraints: {
        maxSizeBytes: number;
        allowedMimeTypes: string[];
    };
}
export interface CompleteKycUploadRequest {
    kycCaseId: string;
    documentType: string;
    fileKey: string;
    originalFileName: string;
    mimeType: string;
    sizeBytes: number;
}
export interface CompleteKycUploadResponse {
    documentId: string;
    kycCaseId: string;
    uploadStatus: "UPLOADED" | "SCANNING" | "AVAILABLE";
}
