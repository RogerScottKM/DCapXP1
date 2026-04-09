"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.applyReferralCode = applyReferralCode;
exports.getMyReferralStatus = getMyReferralStatus;
const referrals_service_1 = require("./referrals.service");
async function applyReferralCode(req, res, next) {
    try {
        const result = await referrals_service_1.referralsService.apply(req.auth.userId, req.body);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
async function getMyReferralStatus(req, res, next) {
    try {
        const result = await referrals_service_1.referralsService.getMyStatus(req.auth.userId);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
