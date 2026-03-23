import type {
  CompleteKycUploadRequest,
  CompleteKycUploadResponse,
  PresignUploadRequest,
  PresignUploadResponse,
} from "@dcapx/contracts";
import { apiFetch } from "./client";

export function presignUpload(body: PresignUploadRequest) {
  return apiFetch<PresignUploadResponse>("/api/uploads/presign", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function completeKycUpload(body: CompleteKycUploadRequest) {
  return apiFetch<CompleteKycUploadResponse>("/api/uploads/complete", {
    method: "POST",
    body: JSON.stringify(body),
  });
}
