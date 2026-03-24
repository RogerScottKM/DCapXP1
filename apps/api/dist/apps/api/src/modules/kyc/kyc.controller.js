"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getMyKycCase = getMyKycCase;
exports.createMyKycCase = createMyKycCase;
const kyc_service_1 = require("./kyc.service");
async function getMyKycCase(req, res, next) {
    try {
        const result = await kyc_service_1.kycService.getMyKycCase(req.auth.userId);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
async function createMyKycCase(req, res, next) {
    try {
        const result = await kyc_service_1.kycService.createMyKycCase(req.auth.userId);
        res.status(201).json(result);
    }
    catch (error) {
        next(error);
    }
}
