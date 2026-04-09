import type { EmailPayload, EmailProvider, EmailSendResult } from "../notifications.types";

export class ConsoleEmailProvider implements EmailProvider {
  async send(payload: EmailPayload): Promise<EmailSendResult> {
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
