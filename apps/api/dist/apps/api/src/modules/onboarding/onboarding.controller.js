"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getMyOnboardingStatus = getMyOnboardingStatus;
const onboarding_service_1 = require("./onboarding.service");
async function getMyOnboardingStatus(req, res, next) { try {
    const userId = req.auth.userId;
    const result = await onboarding_service_1.onboardingService.getMyOnboardingStatus(userId);
    res.json(result);
}
catch (error) {
    next(error);
} }
