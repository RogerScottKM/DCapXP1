"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createInvitation = createInvitation;
exports.getInvitationByToken = getInvitationByToken;
exports.acceptInvitation = acceptInvitation;
const invitations_service_1 = require("./invitations.service");
async function createInvitation(req, res, next) {
    try {
        const invitedByUserId = req.auth.userId;
        const body = req.body;
        const result = await invitations_service_1.invitationsService.createInvitation(invitedByUserId, body);
        res.status(201).json(result);
    }
    catch (error) {
        next(error);
    }
}
async function getInvitationByToken(req, res, next) {
    try {
        const { token } = req.params;
        const result = await invitations_service_1.invitationsService.getInvitationByToken(token);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
async function acceptInvitation(req, res, next) {
    try {
        const { token } = req.params;
        const acceptedUserId = req.auth.userId;
        const body = req.body;
        const result = await invitations_service_1.invitationsService.acceptInvitation(token, acceptedUserId);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
