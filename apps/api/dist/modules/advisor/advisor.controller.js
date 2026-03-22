"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getAdvisorClientAptivioSummary = getAdvisorClientAptivioSummary;
const advisor_service_1 = require("./advisor.service");
async function getAdvisorClientAptivioSummary(req, res, next) { try {
    const advisorUserId = req.auth.userId;
    const { clientId } = req.params;
    const result = await advisor_service_1.advisorService.getClientAptivioSummary(advisorUserId, clientId);
    res.json(result);
}
catch (error) {
    next(error);
} }
