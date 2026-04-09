export type ReferralAttributionStatus = "PENDING" | "CONFIRMED" | "REJECTED" | "CANCELLED";
export type ReferralApplySource = "LOGIN" | "ONBOARDING" | "INVITATION" | "REGISTER" | "ADMIN" | "IMPORT";
export type RewardUnitType = "POINTS" | "CASH" | "TOKEN" | "PROFIT_SHARE" | "STOCK_OPTION";
export interface ReferralRewardBalanceDto {
    unitType: RewardUnitType;
    balance: number;
    updatedAtUtc: string | null;
}
export interface ReferralAttributionDto {
    id: string;
    status: ReferralAttributionStatus;
    applySource: ReferralApplySource | null;
    referralCode: string;
    referrerUserId: string;
    attributedAtUtc: string;
    confirmedAtUtc: string | null;
    communityKey: string | null;
    regionKey: string | null;
}
export interface GetMyReferralStatusResponse {
    hasAttribution: boolean;
    canApplyReferralCode: boolean;
    lockedReason: string | null;
    referredByCodeInput: string | null;
    attribution: ReferralAttributionDto | null;
    rewards: {
        balances: ReferralRewardBalanceDto[];
        totals: {
            points: number;
            cash: number;
            token: number;
            profitShare: number;
            stockOption: number;
        };
    };
}
export interface ApplyReferralCodeRequest {
    code: string;
    applySource?: ReferralApplySource;
}
export interface ApplyReferralCodeResponse {
    ok: true;
    message: string;
    status: GetMyReferralStatusResponse;
}
