import type { AcceptConsentsRequest, ConsentRecordDto, GetRequiredConsentsResponse } from "@dcapx/contracts";
import { prisma } from "../../db";

const REQUIRED_CONSENTS = [
  { consentType: "TERMS_OF_SERVICE", version: "v1", label: "Terms of Service", required: true },
  { consentType: "PRIVACY_POLICY", version: "v1", label: "Privacy Policy", required: true },
  { consentType: "DATA_PROCESSING", version: "v1", label: "Data Processing", required: true },
  { consentType: "ELECTRONIC_COMMUNICATION", version: "v1", label: "Electronic Communication", required: true },
  { consentType: "APTIVIO_ASSESSMENT_AUTH", version: "v1", label: "Aptivio Assessment Authorisation", required: true },
] as const;

class ConsentsService {
  async getRequiredConsents(userId: string): Promise<GetRequiredConsentsResponse> {
    const existing = await prisma.consentRecord.findMany({ where: { userId, revokedAt: null } });
    const accepted = new Set(existing.map((x) => x.consentType));
    return {
      items: [...REQUIRED_CONSENTS] as any,
      missingConsentTypes: REQUIRED_CONSENTS
        .filter((x) => !accepted.has(x.consentType as any))
        .map((x) => x.consentType) as any,
    };
  }
  async acceptConsents(userId: string, request: AcceptConsentsRequest): Promise<ConsentRecordDto[]> {
    await prisma.$transaction(
      request.items.map((item: AcceptConsentsRequest["items"][number]) =>
        prisma.consentRecord.create({
          data: { userId, consentType: item.consentType as any, version: item.version },
        })
      )
    );
    const saved = await prisma.consentRecord.findMany({
      where: { userId, revokedAt: null },
      orderBy: { acceptedAt: "desc" },
    });
    return saved.map((x) => ({
      consentType: x.consentType as any,
      version: x.version,
      acceptedAtUtc: x.acceptedAt.toISOString(),
      revokedAtUtc: x.revokedAt?.toISOString() ?? null,
    }));
  }
}
export const consentsService = new ConsentsService();
