import { asJson } from "../../lib/prisma-json";
import { Prisma } from "@prisma/client";
import { CreatePaymentMethodDto } from "./payments.dto";

export function mapCreatePaymentMethodDto(
  userId: string,
  dto: CreatePaymentMethodDto,
): Prisma.PaymentMethodCreateInput {
  if (dto.type === "BANK_ACCOUNT") {
    return {
      user: { connect: { id: userId } },
      type: dto.type,
      label: dto.label,
      metadata: asJson(dto.metadata),
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
          metadata: asJson(dto.bankAccount.metadata),
        },
      },
    };
  }

  return {
    user: { connect: { id: userId } },
    type: dto.type,
    label: dto.label,
    metadata: asJson(dto.metadata),
  };
}
