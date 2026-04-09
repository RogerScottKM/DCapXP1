export type EmailPayload = {
  to: string;
  subject: string;
  html: string;
  text?: string;
};

export type EmailSendResult = {
  provider: string;
  providerMessageId?: string | null;
};

export interface EmailProvider {
  send(payload: EmailPayload): Promise<EmailSendResult>;
}
