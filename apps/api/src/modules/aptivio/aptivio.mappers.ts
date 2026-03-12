import { asJson } from "../../lib/prisma-json";
import { Prisma } from "@prisma/client";
import {
  AptivioProfileInitDto,
  CompleteAssessmentDto,
  IssueAptivioIdentityDto,
} from "./aptivio.dto";

export function mapInitAptivioProfileDto(
  userId: string,
  dto: AptivioProfileInitDto,
): Prisma.AptivioProfileCreateInput {
  return {
    user: { connect: { id: userId } },
    status: "DRAFT",
    version: "v1.0.0",
    twinJson: {
      context: {
        primaryRole: dto.primaryRole,
        roleFamily: dto.roleFamily,
        seniority: dto.seniority,
        country: dto.country,
        sourceSystem: dto.sourceSystem,
      },
      metadata: {
        tags: dto.tags ?? [],
      },
      ...(dto.twinJson ?? {}),
    },
  };
}

export function mapIssueAptivioIdentityDto(
  aptivioProfileId: string,
  dto: IssueAptivioIdentityDto,
): Prisma.AptivioIdentityCreateInput {
  return {
    aptivioProfile: { connect: { id: aptivioProfileId } },
    passportNumber: dto.passportNumber,
    status: dto.status,
    claimsJson: asJson(dto.claimsJson),
    tokenEntitlementsJson: asJson(dto.tokenEntitlementsJson),
  };
}
