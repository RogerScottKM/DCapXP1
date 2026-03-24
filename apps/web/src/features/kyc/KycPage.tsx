import React, { useEffect, useMemo, useState } from "react";
import type { ApiErrorResponse } from "@dcapx/contracts";
import { completeKycUpload, presignUpload } from "../../lib/api/uploads";
import {
  createMyKycCase,
  getMyKycCase,
  type MyKycCaseResponse,
} from "../../lib/api/kyc";
import PortalShell from "../ui/PortalShell";

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

function statusPill(status: string | null | undefined) {
  const value = status || "UNKNOWN";

  const classes =
    value === "APPROVED"
      ? "border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200"
      : value === "UNDER_REVIEW" || value === "SUBMITTED"
      ? "border-cyan-300 bg-cyan-50 text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200"
      : value === "REJECTED" || value === "NEEDS_INFO"
      ? "border-rose-300 bg-rose-50 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200"
      : "border-amber-300 bg-amber-50 text-amber-700 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200";

  return (
    <span className={`rounded-full border px-3 py-1 text-xs font-medium ${classes}`}>
      {value}
    </span>
  );
}

function messageBox(kind: "error" | "success", message: string) {
  const classes =
    kind === "error"
      ? "border-rose-300 bg-rose-50 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200"
      : "border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200";

  return (
    <div className={`rounded-2xl border px-4 py-3 text-sm ${classes}`}>
      <span className="font-medium">{kind === "error" ? "Error:" : "Success:"}</span>{" "}
      {message}
    </div>
  );
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
    <PortalShell
      title="KYC Verification"
      description="Create your KYC case, upload identity documents, and track document review status through a controlled verification workflow."
    >
      <div className="grid gap-6">
        {errorMessage ? messageBox("error", errorMessage) : null}
        {successMessage ? messageBox("success", successMessage) : null}

        {isLoading ? (
          <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <p className="text-sm text-slate-600 dark:text-slate-400">
              Loading KYC case...
            </p>
          </div>
        ) : null}

        {!isLoading && !hasCase ? (
          <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
            <h2 className="text-xl font-semibold tracking-tight">No KYC Case Yet</h2>
            <p className="mt-3 text-sm text-slate-600 dark:text-slate-400">
              Create your KYC case to begin document submission.
            </p>
            <button
              type="button"
              onClick={handleCreateCase}
              disabled={isCreatingCase}
              className="mt-5 rounded-2xl border border-cyan-400/40 bg-cyan-400/10 px-5 py-3 text-sm font-medium text-cyan-700 transition hover:bg-cyan-400/20 disabled:cursor-not-allowed disabled:opacity-50 dark:text-cyan-200"
            >
              {isCreatingCase ? "Creating..." : "Create KYC Case"}
            </button>
          </section>
        ) : null}

        {!isLoading && hasCase && kycCase ? (
          <>
            <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
              <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                <div>
                  <h2 className="text-xl font-semibold tracking-tight">Case Summary</h2>
                  <p className="mt-3 text-sm text-slate-600 dark:text-slate-400">
                    Case ID: {kycCase.id}
                  </p>
                </div>

                <div>{statusPill(kycCase.status)}</div>
              </div>

              <div className="mt-6 grid gap-4 sm:grid-cols-2">
                <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
                  <div className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">
                    Created
                  </div>
                  <div className="mt-2 text-sm font-medium">
                    {formatUtc(kycCase.createdAtUtc)}
                  </div>
                </div>

                <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60">
                  <div className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">
                    Updated
                  </div>
                  <div className="mt-2 text-sm font-medium">
                    {formatUtc(kycCase.updatedAtUtc)}
                  </div>
                </div>
              </div>

              {kycCase.notes ? (
                <div className="mt-4 rounded-2xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-700 dark:border-slate-800 dark:bg-slate-950/60 dark:text-slate-300">
                  <span className="font-medium">Notes:</span> {kycCase.notes}
                </div>
              ) : null}
            </section>

            <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
              <h2 className="text-xl font-semibold tracking-tight">Upload Document</h2>

              <form onSubmit={handleUpload} className="mt-6 grid gap-5">
                <div>
                  <label
                    htmlFor="documentType"
                    className="block text-sm font-medium text-slate-700 dark:text-slate-200"
                  >
                    Document Type
                  </label>
                  <select
                    id="documentType"
                    value={documentType}
                    onChange={(e) => setDocumentType(e.target.value)}
                    disabled={isUploading}
                    className="mt-2 w-full max-w-sm rounded-2xl border border-slate-300 bg-white px-4 py-3 text-slate-900 outline-none focus:border-cyan-400 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
                  >
                    {DOCUMENT_TYPE_OPTIONS.map((option) => (
                      <option key={option} value={option}>
                        {option}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label
                    htmlFor="kycFile"
                    className="block text-sm font-medium text-slate-700 dark:text-slate-200"
                  >
                    Choose File
                  </label>
                  <input
                    id="kycFile"
                    type="file"
                    onChange={(e) => setSelectedFile(e.target.files?.[0] || null)}
                    disabled={isUploading}
                    className="mt-2 block text-sm text-slate-700 file:mr-4 file:rounded-xl file:border file:border-slate-300 file:bg-white file:px-4 file:py-2 file:text-sm file:font-medium hover:file:bg-slate-50 dark:text-slate-300 dark:file:border-slate-700 dark:file:bg-slate-900 dark:hover:file:bg-slate-800"
                  />
                </div>

                {selectedFile ? (
                  <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-700 dark:border-slate-800 dark:bg-slate-950/60 dark:text-slate-300">
                    <span className="font-medium">Selected file:</span>{" "}
                    {selectedFile.name} ({selectedFile.size} bytes)
                  </div>
                ) : null}

                <button
                  type="submit"
                  disabled={isUploading || !selectedFile}
                  className="w-fit rounded-2xl border border-cyan-400/40 bg-cyan-400/10 px-5 py-3 text-sm font-medium text-cyan-700 transition hover:bg-cyan-400/20 disabled:cursor-not-allowed disabled:opacity-50 dark:text-cyan-200"
                >
                  {isUploading ? "Uploading..." : "Upload Document"}
                </button>
              </form>
            </section>

            <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900/80">
              <h2 className="text-xl font-semibold tracking-tight">Uploaded Documents</h2>

              {sortedDocuments.length === 0 ? (
                <p className="mt-4 text-sm text-slate-600 dark:text-slate-400">
                  No documents uploaded yet.
                </p>
              ) : (
                <div className="mt-6 grid gap-4">
                  {sortedDocuments.map((doc) => (
                    <div
                      key={doc.id}
                      className="rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/60"
                    >
                      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                        <div>
                          <div className="text-base font-semibold">{doc.docType}</div>
                          <div className="mt-1 text-sm text-slate-600 dark:text-slate-400">
                            {doc.fileName || "—"}
                          </div>
                        </div>

                        {statusPill(doc.uploadStatus)}
                      </div>

                      <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                            MIME
                          </div>
                          <div className="mt-1 text-sm">{doc.mimeType || "—"}</div>
                        </div>

                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                            Size
                          </div>
                          <div className="mt-1 text-sm">{doc.sizeBytes ?? "—"}</div>
                        </div>

                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                            Uploaded
                          </div>
                          <div className="mt-1 text-sm">{formatUtc(doc.uploadedAtUtc)}</div>
                        </div>

                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                            Reviewed
                          </div>
                          <div className="mt-1 text-sm">{formatUtc(doc.reviewedAtUtc)}</div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>
          </>
        ) : null}
      </div>
    </PortalShell>
  );
}
