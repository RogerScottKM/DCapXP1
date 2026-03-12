import { asJson } from "../../lib/prisma-json";
import { Prisma } from "@prisma/client";
import {
  CreateAgentDto,
  CreateAgentKeyDto,
  GrantMandateDto,
} from "./agents.dto";

export function mapCreateAgentDto(userId: string, dto: CreateAgentDto): Prisma.AgentCreateInput {
  return {
    user: { connect: { id: userId } },
    name: dto.name,
    principalType: dto.principalType,
    kind: dto.kind,
    capabilityTier: dto.capabilityTier,
    version: dto.version ?? "1.0",
    
config: asJson(dto.config),
    aptivioTokenId: dto.aptivioTokenId,
    status: "DRAFT",
  };
}

export function mapCreateAgentKeyDto(agentId: string, dto: CreateAgentKeyDto): Prisma.AgentKeyCreateInput {
  return {
    agent: { connect: { id: agentId } },
    credentialType: dto.credentialType,
    publicKeyPem: dto.credentialType === "PUBLIC_KEY" ? dto.publicKeyPem : undefined,
    keyPrefix: dto.credentialType === "API_KEY" ? dto.keyPrefix : undefined,
    keyHash: dto.credentialType === "API_KEY" ? dto.keyHash : undefined,
    expiresAt: dto.expiresAt ? new Date(dto.expiresAt) : undefined,
  };
}

export function mapGrantMandateDto(agentId: string, dto: GrantMandateDto): Prisma.MandateCreateInput {
  return {
    agent: { connect: { id: agentId } },
    action: dto.action,
    market: dto.market,
    maxNotionalPerDay: BigInt(dto.maxNotionalPerDay),
    maxOrdersPerDay: dto.maxOrdersPerDay,
    notBefore: dto.notBefore ? new Date(dto.notBefore) : undefined,
    expiresAt: new Date(dto.expiresAt),
    constraints: asJson(dto.constraints),
    mandateJwtHash: dto.mandateJwtHash,
    status: "ACTIVE",
  };
}
