"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getRequiredConsents = getRequiredConsents;
exports.acceptConsents = acceptConsents;
const consents_service_1 = require("./consents.service");
async function getRequiredConsents(req, res, next) {
    try {
        const userId = req.auth.userId;
        const result = await consents_service_1.consentsService.getRequiredConsents(userId);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
async function acceptConsents(req, res, next) {
    try {
        const userId = req.auth.userId;
        const body = req.body;
        const result = await consents_service_1.consentsService.acceptConsents(userId, body);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
