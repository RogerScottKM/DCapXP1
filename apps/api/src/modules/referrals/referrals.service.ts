import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors/api-error";
import { parseDto } from "../../lib/service/zod";
import { toUtcIso } from "../../lib/time/utc";
import { applyReferralCodeDto } from "./referrals.dto";

class ReferralsService {
  async apply(userId: string, input: unknown) {
    const dto = parseDto(applyReferralCodeDto, input);
    const normalizedCode = dto.code.trim().toUpperCase();

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        referralAttribution: {
          select: { id: true },
        },
      },
    });

    if (!user) {
      throw new ApiError({
        statusCode: 404,
        code: "USER_NOT_FOUND",
        message: "User not found.",
      });
    }

    if (user.referralAttribution) {
      throw new ApiError({
        statusCode: 409,
        code: "REFERRAL_ALREADY_APPLIED",
        message: "A referral code has already been applied to this account.",
      });
    }

    const referralCode = await prisma.referralCode.findUnique({
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
      throw new ApiError({
        statusCode: 404,
        code: "REFERRAL_CODE_INVALID",
        message: "Referral code not found or inactive.",
      });
    }

    if (referralCode.ownerUserId === userId) {
      throw new ApiError({
        statusCode: 400,
        code: "SELF_REFERRAL_NOT_ALLOWED",
        message: "You cannot apply your own referral code.",
      });
    }

    await prisma.$transaction(async (tx) => {
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
      ok: true as const,
      message: "Referral code applied successfully.",
      status,
    };
  }

  async getMyStatus(userId: string) {
    const [user, attribution, balances] = await Promise.all([
      prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          referredByCodeInput: true,
        },
      }),
      prisma.referralAttribution.findUnique({
        where: { referredUserId: userId },
        include: {
          referralCode: {
            select: {
              code: true,
            },
          },
        },
      }),
      prisma.userRewardBalance.findMany({
        where: { userId },
        orderBy: { unitType: "asc" },
      }),
    ]);

    if (!user) {
      throw new ApiError({
        statusCode: 404,
        code: "USER_NOT_FOUND",
        message: "User not found.",
      });
    }

    const mappedBalances = balances.map((b) => ({
      unitType: b.unitType,
      balance: Number(b.balance),
      updatedAtUtc: toUtcIso(b.updatedAt),
    }));

    const totals = {
      points: 0,
      cash: 0,
      token: 0,
      profitShare: 0,
      stockOption: 0,
    };

    for (const row of mappedBalances) {
      if (row.unitType === "POINTS") totals.points += row.balance;
      if (row.unitType === "CASH") totals.cash += row.balance;
      if (row.unitType === "TOKEN") totals.token += row.balance;
      if (row.unitType === "PROFIT_SHARE") totals.profitShare += row.balance;
      if (row.unitType === "STOCK_OPTION") totals.stockOption += row.balance;
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
            attributedAtUtc: toUtcIso(attribution.attributedAt)!,
            confirmedAtUtc: toUtcIso(attribution.confirmedAt),
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

export const referralsService = new ReferralsService();
