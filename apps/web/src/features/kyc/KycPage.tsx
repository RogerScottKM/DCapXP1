import React, { useEffect, useMemo, useState } from "react";
import type { ApiErrorResponse } from "@dcapx/contracts";
import { completeKycUpload, presignUpload } from "../../lib/api/uploads";
import { createMyKycCase, getMyKycCase, type MyKycCaseResponse } from "../../lib/api/kyc";

const DOCUMENT_TYPE_OPTIONS = [
  "PASSPORT",
  "DRIVERS_LICENSE",
  "NATIONAL_ID",
  "PROOF_OF_ADDRESS",
];

function formatUtc(utc: string | null | undefined) {
  if (!utc) return "—";

  const date = new Date(utc);
  if (Number.isNaN(date.getTime())) return utc;

  return new Intl.DateTimeFormat("en-AU", {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(date);
}

export default function KycPage() {
  const [kycCase, setKycCase] = useState<MyKycCaseResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isCreatingCase, setIsCreatingCase] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  const [documentType, setDocumentType] = useState(DOCUMENT_TYPE_OPTIONS[0]);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);

  async function loadKycCase() {
    try {
      setIsLoading(true);
      setErrorMessage(null);

      const result = await getMyKycCase();
      setKycCase(result);
    } catch (error: any) {
      const maybeApiError = error as ApiErrorResponse;
      const code = maybeApiError?.error?.code;

      if (code === "KYC_CASE_NOT_FOUND" || code === "NOT_FOUND") {
        setKycCase(null);
      } else {
        setErrorMessage(
          maybeApiError?.error?.message ||
            error?.message ||
            "Failed to load KYC case."
        );
      }
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    loadKycCase();
  }, []);

  async function handleCreateCase() {
    try {
      setIsCreatingCase(true);
      setErrorMessage(null);
      setSuccessMessage(null);

      const result = await createMyKycCase();
      setKycCase(result);
      setSuccessMessage("KYC case created.");
    } catch (error: any) {
      setErrorMessage(
        error?.error?.message ||
          error?.message ||
          "Failed to create KYC case."
      );
    } finally {
      setIsCreatingCase(false);
    }
  }

  async function handleUpload(e: React.FormEvent) {
    e.preventDefault();

    if (!kycCase) {
      setErrorMessage("Please create a KYC case first.");
      return;
    }

    if (!selectedFile) {
      setErrorMessage("Please choose a file to upload.");
      return;
    }

    try {
      setIsUploading(true);
      setErrorMessage(null);
      setSuccessMessage(null);

      const presigned = await presignUpload({
        purpose: "KYC_DOCUMENT",
        fileName: selectedFile.name,
        mimeType: selectedFile.type || "application/octet-stream",
        sizeBytes: selectedFile.size,
      });

      const uploadResponse = await fetch(presigned.uploadUrl, {
        method: "PUT",
        headers: {
          ...(presigned.headers || {}),
          "Content-Type": selectedFile.type || "application/octet-stream",
        },
        body: selectedFile,
      });

      if (!uploadResponse.ok) {
        throw new Error("Direct file upload failed.");
      }

      await completeKycUpload({
        kycCaseId: kycCase.id,
        documentType,
        fileKey: presigned.fileKey,
        originalFileName: selectedFile.name,
        mimeType: selectedFile.type || "application/octet-stream",
        sizeBytes: selectedFile.size,
      });

      setSelectedFile(null);
      setSuccessMessage("Document uploaded successfully.");
      await loadKycCase();
    } catch (error: any) {
      setErrorMessage(
        error?.error?.message ||
          error?.message ||
          "Failed to upload KYC document."
      );
    } finally {
      setIsUploading(false);
    }
  }

  const hasCase = Boolean(kycCase);

  const sortedDocuments = useMemo(() => {
    return [...(kycCase?.documents || [])].sort((a, b) => {
      const aTime = a.uploadedAtUtc ? new Date(a.uploadedAtUtc).getTime() : 0;
      const bTime = b.uploadedAtUtc ? new Date(b.uploadedAtUtc).getTime() : 0;
      return bTime - aTime;
    });
  }, [kycCase]);

  return (
    <main style={{ maxWidth: 960, margin: "0 auto", padding: 24 }}>
      <h1>KYC Verification</h1>
      <p>
        Create your KYC case, upload identity documents, and track your review status.
      </p>

      {errorMessage ? (
        <div
          style={{
            border: "1px solid #f0b4b4",
            borderRadius: 8,
            padding: 16,
            marginBottom: 16,
          }}
        >
          <strong>Error:</strong> {errorMessage}
        </div>
      ) : null}

      {successMessage ? (
        <div
          style={{
            border: "1px solid #b7e3c0",
            borderRadius: 8,
            padding: 16,
            marginBottom: 16,
          }}
        >
          <strong>Success:</strong> {successMessage}
        </div>
      ) : null}

      {isLoading ? <p>Loading KYC case...</p> : null}

      {!isLoading && !hasCase ? (
        <section
          style={{
            border: "1px solid #ddd",
            borderRadius: 8,
            padding: 16,
            marginBottom: 24,
          }}
        >
          <h2 style={{ marginTop: 0 }}>No KYC Case Yet</h2>
          <p>Create your KYC case to begin document submission.</p>
          <button
            type="button"
            onClick={handleCreateCase}
            disabled={isCreatingCase}
            style={{
              padding: "10px 16px",
              borderRadius: 8,
              border: "1px solid #222",
              cursor: isCreatingCase ? "not-allowed" : "pointer",
            }}
          >
            {isCreatingCase ? "Creating..." : "Create KYC Case"}
          </button>
        </section>
      ) : null}

      {!isLoading && hasCase && kycCase ? (
        <>
          <section
            style={{
              border: "1px solid #ddd",
              borderRadius: 8,
              padding: 16,
              marginBottom: 24,
            }}
          >
            <h2 style={{ marginTop: 0 }}>Case Summary</h2>
            <p><strong>Case ID:</strong> {kycCase.id}</p>
            <p><strong>Status:</strong> {kycCase.status}</p>
            <p><strong>Created:</strong> {formatUtc(kycCase.createdAtUtc)}</p>
            <p><strong>Updated:</strong> {formatUtc(kycCase.updatedAtUtc)}</p>
            {kycCase.notes ? (
              <p><strong>Notes:</strong> {kycCase.notes}</p>
            ) : null}
          </section>

          <section
            style={{
              border: "1px solid #ddd",
              borderRadius: 8,
              padding: 16,
              marginBottom: 24,
            }}
          >
            <h2 style={{ marginTop: 0 }}>Upload Document</h2>

            <form onSubmit={handleUpload} style={{ display: "grid", gap: 16 }}>
              <div>
                <label htmlFor="documentType">Document Type</label>
                <select
                  id="documentType"
                  value={documentType}
                  onChange={(e) => setDocumentType(e.target.value)}
                  disabled={isUploading}
                  style={{ display: "block", marginTop: 6, padding: 10, minWidth: 260 }}
                >
                  {DOCUMENT_TYPE_OPTIONS.map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label htmlFor="kycFile">Choose File</label>
                <input
                  id="kycFile"
                  type="file"
                  onChange={(e) => setSelectedFile(e.target.files?.[0] || null)}
                  disabled={isUploading}
                  style={{ display: "block", marginTop: 6 }}
                />
              </div>

              {selectedFile ? (
                <div>
                  <strong>Selected file:</strong> {selectedFile.name} ({selectedFile.size} bytes)
                </div>
              ) : null}

              <button
                type="submit"
                disabled={isUploading || !selectedFile}
                style={{
                  padding: "10px 16px",
                  borderRadius: 8,
                  border: "1px solid #222",
                  cursor: isUploading || !selectedFile ? "not-allowed" : "pointer",
                  width: "fit-content",
                }}
              >
                {isUploading ? "Uploading..." : "Upload Document"}
              </button>
            </form>
          </section>

          <section
            style={{
              border: "1px solid #ddd",
              borderRadius: 8,
              padding: 16,
            }}
          >
            <h2 style={{ marginTop: 0 }}>Uploaded Documents</h2>

            {sortedDocuments.length === 0 ? (
              <p>No documents uploaded yet.</p>
            ) : (
              <ul style={{ paddingLeft: 20, marginBottom: 0 }}>
                {sortedDocuments.map((doc) => (
                  <li key={doc.id} style={{ marginBottom: 12 }}>
                    <div><strong>{doc.docType}</strong></div>
                    <div>File: {doc.fileName || "—"}</div>
                    <div>MIME: {doc.mimeType || "—"}</div>
                    <div>Size: {doc.sizeBytes ?? "—"}</div>
                    <div>Upload status: {doc.uploadStatus || "—"}</div>
                    <div>Uploaded: {formatUtc(doc.uploadedAtUtc)}</div>
                    <div>Reviewed: {formatUtc(doc.reviewedAtUtc)}</div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      ) : null}
    </main>
  );
}
