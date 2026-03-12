"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createPaymentMethod = createPaymentMethod;
const prisma_1 = require("../../lib/prisma");
const zod_1 = require("../../lib/service/zod");
const tx_1 = require("../../lib/service/tx");
const audit_1 = require("../../lib/service/audit");
const payments_dto_1 = require("./payments.dto");
const payments_mappers_1 = require("./payments.mappers");
async function createPaymentMethod(userId, input) {
    const dto = (0, zod_1.parseDto)(payments_dto_1.createPaymentMethodDto, input);
    return (0, tx_1.withTx)(prisma_1.prisma, async (tx) => {
        const paymentMethod = await tx.paymentMethod.create({
            data: (0, payments_mappers_1.mapCreatePaymentMethodDto)(userId, dto),
            include: { bankAccount: true },
        });
        await (0, audit_1.writeAuditEvent)(tx, {
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
