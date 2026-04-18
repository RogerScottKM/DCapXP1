"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getAlertWebhookUrl = getAlertWebhookUrl;
exports.isAlertingEnabled = isAlertingEnabled;
exports.dispatchRuntimeAlert = dispatchRuntimeAlert;
function getAlertWebhookUrl() {
    const value = process.env.ALERT_WEBHOOK_URL?.trim();
    return value ? value : null;
}
function isAlertingEnabled() {
    return Boolean(getAlertWebhookUrl());
}
async function dispatchRuntimeAlert(input, fetchImpl = fetch) {
    const webhookUrl = getAlertWebhookUrl();
    if (!webhookUrl) {
        return { sent: false, skipped: true };
    }
    const response = await fetchImpl(webhookUrl, {
        method: "POST",
        headers: {
            "content-type": "application/json",
        },
        body: JSON.stringify({
            ts: new Date().toISOString(),
            ...input,
        }),
    });
    return {
        sent: response.ok,
        skipped: false,
        status: response.status,
    };
}
