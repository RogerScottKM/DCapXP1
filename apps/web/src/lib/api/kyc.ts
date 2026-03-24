import { apiFetch } from "./client";

export interface MyKycDocumentDto {
  id: string;
  docType: string;
  fileName: string | null;
  mimeType: string | null;
  sizeBytes: number | null;
  uploadStatus: string | null;
  uploadedAtUtc: string | null;
  reviewedAtUtc: string | null;
}

export interface MyKycCaseResponse {
  id: string;
  status: string;
  createdAtUtc: string;
  updatedAtUtc: string;
  notes?: string | null;
  documents: MyKycDocumentDto[];
}

export function getMyKycCase() {
  return apiFetch<MyKycCaseResponse>("/api/me/kyc-case");
}

export function createMyKycCase() {
  return apiFetch<MyKycCaseResponse>("/api/me/kyc-cases", {
    method: "POST",
    body: JSON.stringify({}),
  });
}
