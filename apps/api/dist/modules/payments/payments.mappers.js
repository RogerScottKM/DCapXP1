"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapCreatePaymentMethodDto = mapCreatePaymentMethodDto;
const prisma_json_1 = require("../../lib/prisma-json");
function mapCreatePaymentMethodDto(userId, dto) {
    if (dto.type === "BANK_ACCOUNT") {
        return {
            user: { connect: { id: userId } },
            type: dto.type,
            label: dto.label,
            metadata: (0, prisma_json_1.asJson)(dto.metadata),
            bankAccount: {
                create: {
                    accountHolderName: dto.bankAccount.accountHolderName,
                    bankName: dto.bankAccount.bankName,
                    country: dto.bankAccount.country,
                    currency: dto.bankAccount.currency,
                    maskedAccountNumber: dto.bankAccount.maskedAccountNumber,
                    maskedRoutingNumber: dto.bankAccount.maskedRoutingNumber,
                    ibanMasked: dto.bankAccount.ibanMasked,
                    swiftBicMasked: dto.bankAccount.swiftBicMasked,
                    metadata: (0, prisma_json_1.asJson)(dto.bankAccount.metadata),
                },
            },
        };
    }
    return {
        user: { connect: { id: userId } },
        type: dto.type,
        label: dto.label,
        metadata: (0, prisma_json_1.asJson)(dto.metadata),
    };
}
