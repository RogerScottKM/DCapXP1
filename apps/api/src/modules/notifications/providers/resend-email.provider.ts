import type { EmailPayload, EmailProvider, EmailSendResult } from "../notifications.types";

export class ResendEmailProvider implements EmailProvider {
  constructor(
    private readonly apiKey: string,
    private readonly from: string
  ) {}

  async send(payload: EmailPayload): Promise<EmailSendResult> {
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

    let data: any = null;
    try {
      data = JSON.parse(raw);
    } catch {
      data = null;
    }

    return {
      provider: "resend",
      providerMessageId: data?.id ?? null,
    };
  }
}
