"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.referralsService = void 0;
const prisma_1 = require("../../lib/prisma");
const api_error_1 = require("../../lib/errors/api-error");
const zod_1 = require("../../lib/service/zod");
const utc_1 = require("../../lib/time/utc");
const referrals_dto_1 = require("./referrals.dto");
class ReferralsService {
    async apply(userId, input) {
        const dto = (0, zod_1.parseDto)(referrals_dto_1.applyReferralCodeDto, input);
        const normalizedCode = dto.code.trim().toUpperCase();
        const user = await prisma_1.prisma.user.findUnique({
            where: { id: userId },
            select: {
                id: true,
                referralAttribution: {
                    select: { id: true },
                },
            },
        });
        if (!user) {
            throw new api_error_1.ApiError({
                statusCode: 404,
                code: "USER_NOT_FOUND",
                message: "User not found.",
            });
        }
        if (user.referralAttribution) {
            throw new api_error_1.ApiError({
                statusCode: 409,
                code: "REFERRAL_ALREADY_APPLIED",
                message: "A referral code has already been applied to this account.",
            });
        }
        const referralCode = await prisma_1.prisma.referralCode.findUnique({
            where: { code: normalizedCode },
            select: {
                id: true,
                code: true,
                status: true,
                ownerUserId: true,
                communityKey: true,
                regionKey: true,
            },
        });
        if (!referralCode || referralCode.status !== "ACTIVE") {
            throw new api_error_1.ApiError({
                statusCode: 404,
                code: "REFERRAL_CODE_INVALID",
                message: "Referral code not found or inactive.",
            });
        }
        if (referralCode.ownerUserId === userId) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "SELF_REFERRAL_NOT_ALLOWED",
                message: "You cannot apply your own referral code.",
            });
        }
        await prisma_1.prisma.$transaction(async (tx) => {
            await tx.referralAttribution.create({
                data: {
                    referredUserId: userId,
                    referralCodeId: referralCode.id,
                    referrerUserId: referralCode.ownerUserId,
                    status: "PENDING",
                    applySource: dto.applySource,
                    communityKey: referralCode.communityKey,
                    regionKey: referralCode.regionKey,
                    lineageSnapshot: {
                        level0: {
                            referrerUserId: referralCode.ownerUserId,
                            referralCode: referralCode.code,
                        },
                    },
                },
            });
            await tx.user.update({
                where: { id: userId },
                data: {
                    referredByCodeInput: referralCode.code,
                    acquisitionSource: "REFERRAL_CODE",
                },
            });
        });
        const status = await this.getMyStatus(userId);
        return {
            ok: true,
            message: "Referral code applied successfully.",
            status,
        };
    }
    async getMyStatus(userId) {
        const [user, attribution, balances] = await Promise.all([
            prisma_1.prisma.user.findUnique({
                where: { id: userId },
                select: {
                    id: true,
                    referredByCodeInput: true,
                },
            }),
            prisma_1.prisma.referralAttribution.findUnique({
                where: { referredUserId: userId },
                include: {
                    referralCode: {
                        select: {
                            code: true,
                        },
                    },
                },
            }),
            prisma_1.prisma.userRewardBalance.findMany({
                where: { userId },
                orderBy: { unitType: "asc" },
            }),
        ]);
        if (!user) {
            throw new api_error_1.ApiError({
                statusCode: 404,
                code: "USER_NOT_FOUND",
                message: "User not found.",
            });
        }
        const mappedBalances = balances.map((b) => ({
            unitType: b.unitType,
            balance: Number(b.balance),
            updatedAtUtc: (0, utc_1.toUtcIso)(b.updatedAt),
        }));
        const totals = {
            points: 0,
            cash: 0,
            token: 0,
            profitShare: 0,
            stockOption: 0,
        };
        for (const row of mappedBalances) {
            if (row.unitType === "POINTS")
                totals.points += row.balance;
            if (row.unitType === "CASH")
                totals.cash += row.balance;
            if (row.unitType === "TOKEN")
                totals.token += row.balance;
            if (row.unitType === "PROFIT_SHARE")
                totals.profitShare += row.balance;
            if (row.unitType === "STOCK_OPTION")
                totals.stockOption += row.balance;
        }
        return {
            hasAttribution: Boolean(attribution),
            canApplyReferralCode: !attribution,
            lockedReason: attribution
                ? "Referral attribution already exists for this user."
                : null,
            referredByCodeInput: user.referredByCodeInput ?? null,
            attribution: attribution
                ? {
                    id: attribution.id,
                    status: attribution.status,
                    applySource: attribution.applySource ?? null,
                    referralCode: attribution.referralCode.code,
                    referrerUserId: attribution.referrerUserId,
                    attributedAtUtc: (0, utc_1.toUtcIso)(attribution.attributedAt),
                    confirmedAtUtc: (0, utc_1.toUtcIso)(attribution.confirmedAt),
                    communityKey: attribution.communityKey ?? null,
                    regionKey: attribution.regionKey ?? null,
                }
                : null,
            rewards: {
                balances: mappedBalances,
                totals,
            },
        };
    }
}
exports.referralsService = new ReferralsService();
