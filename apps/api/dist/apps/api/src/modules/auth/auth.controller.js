"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.login = login;
exports.register = register;
exports.getSession = getSession;
exports.logout = logout;
const auth_service_1 = require("./auth.service");
async function login(req, res, next) {
    try {
        const result = await auth_service_1.authService.login(req, res, req.body);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
async function register(req, res, next) {
    try {
        const user = await (0, auth_service_1.registerUser)(req.body);
        res.status(201).json({
            ok: true,
            user: {
                id: user.id,
                email: user.email,
                username: user.username,
            },
        });
    }
    catch (error) {
        next(error);
    }
}
async function getSession(req, res, next) {
    try {
        const result = await auth_service_1.authService.getSession(req);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
async function logout(req, res, next) {
    try {
        const result = await auth_service_1.authService.logout(req, res);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}
