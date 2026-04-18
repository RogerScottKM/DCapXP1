import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  dispatchRuntimeAlert,
  getAlertWebhookUrl,
  isAlertingEnabled,
} from "../src/lib/runtime/alerting";

describe("runtime alerting", () => {
  beforeEach(() => {
    delete process.env.ALERT_WEBHOOK_URL;
  });

  it("skips dispatch when no webhook is configured", async () => {
    expect(getAlertWebhookUrl()).toBeNull();
    expect(isAlertingEnabled()).toBe(false);

    const result = await dispatchRuntimeAlert({
      type: "RECONCILIATION_FAILURE",
      summary: "test",
      payload: { checkCount: 4 },
    }, vi.fn() as any);

    expect(result).toEqual({ sent: false, skipped: true });
  });

  it("posts alert payloads when a webhook is configured", async () => {
    process.env.ALERT_WEBHOOK_URL = "https://alerts.example.test/hook";
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 202,
    });

    const result = await dispatchRuntimeAlert({
      type: "RECONCILIATION_FAILURE",
      summary: "reconciliation failed",
      payload: { failureCount: 2 },
    }, fetchMock as any);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][0]).toBe("https://alerts.example.test/hook");
    expect(result).toEqual({ sent: true, skipped: false, status: 202 });
  });
});
