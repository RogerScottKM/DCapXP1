"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ResendEmailProvider = void 0;
class ResendEmailProvider {
    apiKey;
    from;
    constructor(apiKey, from) {
        this.apiKey = apiKey;
        this.from = from;
    }
    async send(payload) {
        const response = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${this.apiKey}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                from: this.from,
                to: [payload.to],
                subject: payload.subject,
                html: payload.html,
                text: payload.text,
            }),
        });
        const raw = await response.text();
        if (!response.ok) {
            throw new Error(`Resend send failed (${response.status}): ${raw}`);
        }
        let data = null;
        try {
            data = JSON.parse(raw);
        }
        catch {
            data = null;
        }
        return {
            provider: "resend",
            providerMessageId: data?.id ?? null,
        };
    }
}
exports.ResendEmailProvider = ResendEmailProvider;
