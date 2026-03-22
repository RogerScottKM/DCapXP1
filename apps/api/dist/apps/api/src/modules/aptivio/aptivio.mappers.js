"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapInitAptivioProfileDto = mapInitAptivioProfileDto;
exports.mapIssueAptivioIdentityDto = mapIssueAptivioIdentityDto;
const prisma_json_1 = require("../../lib/prisma-json");
function mapInitAptivioProfileDto(userId, dto) {
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
function mapIssueAptivioIdentityDto(aptivioProfileId, dto) {
    return {
        aptivioProfile: { connect: { id: aptivioProfileId } },
        passportNumber: dto.passportNumber,
        status: dto.status,
        claimsJson: (0, prisma_json_1.asJson)(dto.claimsJson),
        tokenEntitlementsJson: (0, prisma_json_1.asJson)(dto.tokenEntitlementsJson),
    };
}
