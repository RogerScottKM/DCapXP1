"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ConsoleEmailProvider = void 0;
class ConsoleEmailProvider {
    async send(payload) {
        console.log("[email:console]", {
            to: payload.to,
            subject: payload.subject,
            text: payload.text,
        });
        return {
            provider: "console",
            providerMessageId: null,
        };
    }
}
exports.ConsoleEmailProvider = ConsoleEmailProvider;
