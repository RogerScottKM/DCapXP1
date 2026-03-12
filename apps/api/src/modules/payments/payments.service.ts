import { prisma } from "../../lib/prisma";
import { parseDto } from "../../lib/service/zod";
import { withTx } from "../../lib/service/tx";
import { writeAuditEvent } from "../../lib/service/audit";
import {
  createPaymentMethodDto,
  updateOwnPaymentMethodDto,
  adminUpdatePaymentMethodStatusDto,
} from "./payments.dto";
import { mapCreatePaymentMethodDto } from "./payments.mappers";

export async function createPaymentMethod(userId: string, input: unknown) {
  const dto = parseDto(createPaymentMethodDto, input);

  return withTx(prisma, async (tx) => {
    const paymentMethod = await tx.paymentMethod.create({
      data: mapCreatePaymentMethodDto(userId, dto),
      include: { bankAccount: true },
    });

    await writeAuditEvent(tx, {
      actorType: "USER",
      actorId: userId,
      action: "PAYMENT_METHOD_ADDED",
      resourceType: "PaymentMethod",
      resourceId: paymentMethod.id,
      metadata: { type: paymentMethod.type },
    });

    return paymentMethod;
  });
}
