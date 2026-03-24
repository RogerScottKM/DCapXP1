import { prisma } from "../../db";
import { ApiError } from "../../lib/errors/api-error";

class KycService {
  async getMyKycCase(userId: string) {
    const kycCase = await prisma.kycCase.findFirst({
      where: { userId },
      orderBy: { createdAt: "desc" },
      include: {
        documents: {
          orderBy: { uploadedAt: "desc" },
        },
      },
    });

    if (!kycCase) {
      throw new ApiError({
        statusCode: 404,
        code: "KYC_CASE_NOT_FOUND",
        message: "No KYC case found for this user.",
      });
    }

    return {
      id: kycCase.id,
      status: kycCase.status,
      createdAtUtc: kycCase.createdAt.toISOString(),
      updatedAtUtc: kycCase.updatedAt.toISOString(),
      notes: (kycCase as any).notes ?? null,
      documents: kycCase.documents.map((doc) => ({
        id: doc.id,
        docType: doc.docType,
        fileName: doc.fileName ?? null,
        mimeType: doc.mimeType ?? null,
        sizeBytes: doc.sizeBytes ?? null,
        uploadStatus: (doc as any).uploadStatus ?? null,
        uploadedAtUtc: doc.uploadedAt?.toISOString?.() ?? doc.createdAt.toISOString(),
        reviewedAtUtc: doc.reviewedAt?.toISOString?.() ?? null,
      })),
    };
  }

  async createMyKycCase(userId: string) {
    const kycCase = await prisma.kycCase.create({
      data: { userId },
      include: {
        documents: true,
      },
    });

    return {
      id: kycCase.id,
      status: kycCase.status,
      createdAtUtc: kycCase.createdAt.toISOString(),
      updatedAtUtc: kycCase.updatedAt.toISOString(),
      notes: (kycCase as any).notes ?? null,
      documents: [],
    };
  }
}

export const kycService = new KycService();
