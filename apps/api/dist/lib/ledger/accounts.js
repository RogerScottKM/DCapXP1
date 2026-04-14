"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SYSTEM_LEDGER_OWNER_REF = void 0;
exports.ensureLedgerAccount = ensureLedgerAccount;
exports.ensureUserLedgerAccounts = ensureUserLedgerAccounts;
exports.ensureSystemLedgerAccounts = ensureSystemLedgerAccounts;
const client_1 = require("@prisma/client");
const prisma_1 = require("../prisma");
exports.SYSTEM_LEDGER_OWNER_REF = "SYSTEM";
async function ensureLedgerAccount(input, db = prisma_1.prisma) {
    const ownerRef = String(input.ownerRef ?? "").trim();
    const assetCode = String(input.assetCode ?? "").trim().toUpperCase();
    const existing = await db.ledgerAccount.findFirst({
        where: {
            ownerType: input.ownerType,
            ownerRef,
            assetCode,
            mode: input.mode,
            accountType: input.accountType,
        },
    });
    if (existing) {
        return existing;
    }
    return db.ledgerAccount.create({
        data: {
            ownerType: input.ownerType,
            ownerRef,
            assetCode,
            mode: input.mode,
            accountType: input.accountType,
            status: "ACTIVE",
        },
    });
}
async function ensureUserLedgerAccounts(params, db = prisma_1.prisma) {
    const ownerType = client_1.LedgerAccountOwnerType.USER;
    const ownerRef = params.userId;
    const [available, held] = await Promise.all([
        ensureLedgerAccount({
            ownerType,
            ownerRef,
            assetCode: params.assetCode,
            mode: params.mode,
            accountType: client_1.LedgerAccountType.USER_AVAILABLE,
        }, db),
        ensureLedgerAccount({
            ownerType,
            ownerRef,
            assetCode: params.assetCode,
            mode: params.mode,
            accountType: client_1.LedgerAccountType.USER_HELD,
        }, db),
    ]);
    return { available, held };
}
async function ensureSystemLedgerAccounts(params, db = prisma_1.prisma) {
    const ownerType = client_1.LedgerAccountOwnerType.SYSTEM;
    const ownerRef = exports.SYSTEM_LEDGER_OWNER_REF;
    const [inventory, feeRevenue, treasury, suspense] = await Promise.all([
        ensureLedgerAccount({
            ownerType,
            ownerRef,
            assetCode: params.assetCode,
            mode: params.mode,
            accountType: client_1.LedgerAccountType.EXCHANGE_INVENTORY,
        }, db),
        ensureLedgerAccount({
            ownerType,
            ownerRef,
            assetCode: params.assetCode,
            mode: params.mode,
            accountType: client_1.LedgerAccountType.FEE_REVENUE,
        }, db),
        ensureLedgerAccount({
            ownerType,
            ownerRef,
            assetCode: params.assetCode,
            mode: params.mode,
            accountType: client_1.LedgerAccountType.TREASURY,
        }, db),
        ensureLedgerAccount({
            ownerType,
            ownerRef,
            assetCode: params.assetCode,
            mode: params.mode,
            accountType: client_1.LedgerAccountType.SUSPENSE,
        }, db),
    ]);
    return { inventory, feeRevenue, treasury, suspense };
}
