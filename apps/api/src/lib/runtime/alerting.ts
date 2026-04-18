export type RuntimeAlertInput = {
  type: "RECONCILIATION_FAILURE" | "RUNTIME_ALERT";
  summary: string;
  payload: Record<string, unknown>;
};

export type RuntimeAlertDispatchResult = {
  sent: boolean;
  skipped: boolean;
  status?: number;
};

export function getAlertWebhookUrl(): string | null {
  const value = process.env.ALERT_WEBHOOK_URL?.trim();
  return value ? value : null;
}

export function isAlertingEnabled(): boolean {
  return Boolean(getAlertWebhookUrl());
}

export async function dispatchRuntimeAlert(
  input: RuntimeAlertInput,
  fetchImpl: typeof fetch = fetch,
): Promise<RuntimeAlertDispatchResult> {
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
