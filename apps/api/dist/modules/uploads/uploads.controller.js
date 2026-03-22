"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.presignUpload = presignUpload;
exports.completeKycUpload = completeKycUpload;
const uploads_service_1 = require("./uploads.service");
async function presignUpload(req, res, next) {
    try {
        const userId = req.auth.userId;
        const body = req.body;
        const result = await uploads_service_1.uploadsService.presignUpload(body, userId);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
async function completeKycUpload(req, res, next) {
    try {
        const userId = req.auth.userId;
        const body = req.body;
        const result = await uploads_service_1.uploadsService.completeKycUpload(body, userId);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
