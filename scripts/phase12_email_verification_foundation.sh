#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

echo "==> Detecting password hash field ..."
PASSWORD_FIELD="$(rg -o 'passwordHash|hashedPassword' apps/api/prisma/schema.prisma apps/api/src 2>/dev/null | head -1 || true)"
if [ -z "${PASSWORD_FIELD}" ]; then
  PASSWORD_FIELD="passwordHash"
fi
echo "Using password field: ${PASSWORD_FIELD}"

echo "==> Backing up key files ..."
backup apps/api/prisma/schema.prisma
backup apps/api/src/app.ts
backup apps/api/src/modules/onboarding/onboarding.service.ts
backup apps/api/package.json

mkdir -p apps/api/src/modules/notifications/providers
mkdir -p apps/api/src/modules/verification
mkdir -p scripts

echo "==> Ensuring api package has argon2 ..."
node <<'NODE'
const fs = require("fs");
const path = "apps/api/package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
pkg.dependencies = pkg.dependencies || {};
if (!pkg.dependencies.argon2) {
  pkg.dependencies.argon2 = "^0.41.1";
}
fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo "==> Patching Prisma schema ..."
python3 - <<'PY'
from pathlib import Path

p = Path("apps/api/prisma/schema.prisma")
text = p.read_text()

# Add user fields if missing
if "emailVerifiedAt" not in text or "verificationChallenges" not in text or "notificationDeliveries" not in text:
    marker = "model User {"
    if marker not in text:
        raise SystemExit("Could not find model User in schema.prisma")
    insertion = """
  emailVerifiedAt       DateTime?
  phoneVerifiedAt       DateTime?
  verificationChallenges VerificationChallenge[]
  notificationDeliveries NotificationDelivery[]
""".rstrip()
    text = text.replace(marker, marker + "\n" + insertion, 1)

# Append enums / models if missing
blocks = []

if "enum VerificationChannel" not in text:
    blocks.append("""
enum VerificationChannel {
  EMAIL
  SMS
}
""".strip())

if "enum VerificationPurpose" not in text:
    blocks.append("""
enum VerificationPurpose {
  CONTACT_VERIFY
  PASSWORD_RESET
  MFA
}
""".strip())

if "enum VerificationStatus" not in text:
    blocks.append("""
enum VerificationStatus {
  PENDING
  VERIFIED
  EXPIRED
  LOCKED
  CANCELLED
}
""".strip())

if "model VerificationChallenge" not in text:
    blocks.append("""
model VerificationChallenge {
  id                String               @id @default(cuid())
  userId            String
  user              User                 @relation(fields: [userId], references: [id], onDelete: Cascade)
  channel           VerificationChannel
  purpose           VerificationPurpose
  destinationMasked String
  destinationHash   String
  codeHash          String
  expiresAt         DateTime
  consumedAt        DateTime?
  attemptCount      Int                  @default(0)
  maxAttempts       Int                  @default(5)
  status            VerificationStatus   @default(PENDING)
  providerMessageId String?
  metadata          Json?
  createdAt         DateTime             @default(now())
  updatedAt         DateTime             @updatedAt

  @@index([userId, channel, purpose, status])
  @@index([destinationHash, purpose, status])
}
""".strip())

if "model NotificationDelivery" not in text:
    blocks.append("""
model NotificationDelivery {
  id                String               @id @default(cuid())
  userId            String?
  user              User?                @relation(fields: [userId], references: [id], onDelete: SetNull)
  channel           VerificationChannel
  templateKey       String
  provider          String
  destinationMasked String
  providerMessageId String?
  status            String
  errorCode         String?
  errorMessage      String?
  metadata          Json?
  createdAt         DateTime             @default(now())
  updatedAt         DateTime             @updatedAt

  @@index([userId, channel, templateKey, status])
}
""".strip())

if blocks:
    text = text.rstrip() + "\n\n" + "\n\n".join(blocks) + "\n"

p.write_text(text)
print("Patched schema.prisma")
PY

echo "==> Writing notifications config ..."
cat > apps/api/src/modules/notifications/notifications.config.ts <<'EOF'
export type EmailProviderName = "console" | "resend";

export const notificationsConfig = {
  appBaseUrl: process.env.APP_BASE_URL ?? "http://localhost:3002",
  emailProvider: (process.env.EMAIL_PROVIDER ?? (process.env.RESEND_API_KEY ? "resend" : "console")) as EmailProviderName,
  emailFrom: process.env.EMAIL_FROM ?? "DCapX <no-reply@dcapitalx.local>",
  resendApiKey: process.env.RESEND_API_KEY ?? "",
  otpHmacSecret:
    process.env.OTP_HMAC_SECRET ??
    process.env.SESSION_SECRET ??
    process.env.JWT_SECRET ??
    "dev-only-change-me",
  verificationOtpMinutes: Number(process.env.VERIFICATION_OTP_MINUTES ?? 10),
  resetLinkMinutes: Number(process.env.RESET_LINK_MINUTES ?? 30),
};
EOF

echo "==> Writing notifications types ..."
cat > apps/api/src/modules/notifications/notifications.types.ts <<'EOF'
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
EOF

echo "==> Writing console email provider ..."
cat > apps/api/src/modules/notifications/providers/console-email.provider.ts <<'EOF'
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
EOF

echo "==> Writing Resend email provider ..."
cat > apps/api/src/modules/notifications/providers/resend-email.provider.ts <<'EOF'
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
EOF

echo "==> Writing notification service ..."
cat > apps/api/src/modules/notifications/notification.service.ts <<'EOF'
import { prisma } from "../../lib/prisma";
import { notificationsConfig } from "./notifications.config";
import type { EmailProvider } from "./notifications.types";
import { ConsoleEmailProvider } from "./providers/console-email.provider";
import { ResendEmailProvider } from "./providers/resend-email.provider";

function maskEmail(email: string): string {
  const [local, domain] = email.split("@");
  if (!local || !domain) return email;
  const shown = local.length <= 2 ? local[0] ?? "*" : `${local.slice(0, 2)}***`;
  return `${shown}@${domain}`;
}

function getEmailProvider(): EmailProvider {
  if (notificationsConfig.emailProvider === "resend") {
    if (!notificationsConfig.resendApiKey) {
      throw new Error("RESEND_API_KEY is required when EMAIL_PROVIDER=resend");
    }
    return new ResendEmailProvider(
      notificationsConfig.resendApiKey,
      notificationsConfig.emailFrom
    );
  }
  return new ConsoleEmailProvider();
}

export class NotificationService {
  private readonly emailProvider = getEmailProvider();

  async sendVerificationOtpEmail(args: {
    userId: string;
    to: string;
    code: string;
  }): Promise<void> {
    const subject = "Verify your DCapX email";
    const html = `
      <div style="font-family:Arial,sans-serif;line-height:1.5">
        <h2>Verify your DCapX email</h2>
        <p>Your verification code is:</p>
        <p style="font-size:28px;font-weight:700;letter-spacing:4px">${args.code}</p>
        <p>This code expires in ${notificationsConfig.verificationOtpMinutes} minutes.</p>
      </div>
    `;
    const text = `Your DCapX verification code is ${args.code}. It expires in ${notificationsConfig.verificationOtpMinutes} minutes.`;

    let providerMessageId: string | null = null;
    let status = "SENT";
    let errorCode: string | null = null;
    let errorMessage: string | null = null;
    let provider = notificationsConfig.emailProvider;

    try {
      const result = await this.emailProvider.send({
        to: args.to,
        subject,
        html,
        text,
      });
      provider = result.provider;
      providerMessageId = result.providerMessageId ?? null;
    } catch (error: any) {
      status = "FAILED";
      errorCode = "EMAIL_SEND_FAILED";
      errorMessage = error?.message ?? "Unknown email provider error";
      throw error;
    } finally {
      await prisma.notificationDelivery.create({
        data: {
          userId: args.userId,
          channel: "EMAIL",
          templateKey: "VERIFY_EMAIL_OTP",
          provider,
          destinationMasked: maskEmail(args.to),
          providerMessageId,
          status,
          errorCode,
          errorMessage,
          metadata: null,
        },
      });
    }
  }

  async sendPasswordResetEmail(args: {
    userId: string;
    to: string;
    resetUrl: string;
  }): Promise<void> {
    const subject = "Reset your DCapX password";
    const html = `
      <div style="font-family:Arial,sans-serif;line-height:1.5">
        <h2>Reset your DCapX password</h2>
        <p>Use the link below to reset your password:</p>
        <p><a href="${args.resetUrl}">${args.resetUrl}</a></p>
        <p>This link expires in ${notificationsConfig.resetLinkMinutes} minutes.</p>
      </div>
    `;
    const text = `Reset your DCapX password using this link: ${args.resetUrl}. It expires in ${notificationsConfig.resetLinkMinutes} minutes.`;

    let providerMessageId: string | null = null;
    let status = "SENT";
    let errorCode: string | null = null;
    let errorMessage: string | null = null;
    let provider = notificationsConfig.emailProvider;

    try {
      const result = await this.emailProvider.send({
        to: args.to,
        subject,
        html,
        text,
      });
      provider = result.provider;
      providerMessageId = result.providerMessageId ?? null;
    } catch (error: any) {
      status = "FAILED";
      errorCode = "EMAIL_SEND_FAILED";
      errorMessage = error?.message ?? "Unknown email provider error";
      throw error;
    } finally {
      await prisma.notificationDelivery.create({
        data: {
          userId: args.userId,
          channel: "EMAIL",
          templateKey: "PASSWORD_RESET",
          provider,
          destinationMasked: maskEmail(args.to),
          providerMessageId,
          status,
          errorCode,
          errorMessage,
          metadata: null,
        },
      });
    }
  }
}

export const notificationService = new NotificationService();
EOF

echo "==> Writing verification utils ..."
cat > apps/api/src/modules/verification/verification.utils.ts <<'EOF'
import crypto from "crypto";
import { notificationsConfig } from "../notifications/notifications.config";

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function maskEmail(email: string): string {
  const [local, domain] = normalizeEmail(email).split("@");
  if (!local || !domain) return email;
  const shown = local.length <= 2 ? local[0] ?? "*" : `${local.slice(0, 2)}***`;
  return `${shown}@${domain}`;
}

export function hashForStorage(value: string): string {
  return crypto
    .createHmac("sha256", notificationsConfig.otpHmacSecret)
    .update(value)
    .digest("hex");
}

export function generateOtpCode(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

export function generateOpaqueToken(): string {
  return crypto.randomBytes(32).toString("hex");
}

export function addMinutes(minutes: number): Date {
  return new Date(Date.now() + minutes * 60 * 1000);
}
EOF

echo "==> Writing verification service ..."
cat > apps/api/src/modules/verification/verification.service.ts <<EOF
import argon2 from "argon2";
import { prisma } from "../../lib/prisma";
import { notificationService } from "../notifications/notification.service";
import { notificationsConfig } from "../notifications/notifications.config";
import {
  addMinutes,
  generateOpaqueToken,
  generateOtpCode,
  hashForStorage,
  maskEmail,
  normalizeEmail,
} from "./verification.utils";

export class VerificationService {
  async requestEmailVerification(emailInput: string) {
    const email = normalizeEmail(emailInput);

    const user = await prisma.user.findFirst({
      where: { email },
    });

    if (!user) {
      return { ok: true, message: "If an account exists, a verification email has been sent." };
    }

    if ((user as any).emailVerifiedAt) {
      return { ok: true, message: "Email already verified." };
    }

    await prisma.verificationChallenge.updateMany({
      where: {
        userId: user.id,
        channel: "EMAIL",
        purpose: "CONTACT_VERIFY",
        status: "PENDING",
      },
      data: {
        status: "CANCELLED",
      },
    });

    const code = generateOtpCode();
    const destinationHash = hashForStorage(email);
    const codeHash = hashForStorage(code);

    const challenge = await prisma.verificationChallenge.create({
      data: {
        userId: user.id,
        channel: "EMAIL",
        purpose: "CONTACT_VERIFY",
        destinationMasked: maskEmail(email),
        destinationHash,
        codeHash,
        expiresAt: addMinutes(notificationsConfig.verificationOtpMinutes),
        maxAttempts: 5,
        status: "PENDING",
      },
    });

    await notificationService.sendVerificationOtpEmail({
      userId: user.id,
      to: email,
      code,
    });

    return {
      ok: true,
      message: "If an account exists, a verification email has been sent.",
      challengeId: challenge.id,
    };
  }

  async confirmEmailVerification(emailInput: string, codeInput: string) {
    const email = normalizeEmail(emailInput);
    const destinationHash = hashForStorage(email);
    const codeHash = hashForStorage(codeInput.trim());

    const challenge = await prisma.verificationChallenge.findFirst({
      where: {
        channel: "EMAIL",
        purpose: "CONTACT_VERIFY",
        destinationHash,
        status: "PENDING",
      },
      orderBy: { createdAt: "desc" },
    });

    if (!challenge) {
      throw new Error("Invalid or expired verification code.");
    }

    const now = new Date();

    if (challenge.expiresAt <= now) {
      await prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: { status: "EXPIRED" },
      });
      throw new Error("Invalid or expired verification code.");
    }

    if (challenge.attemptCount >= challenge.maxAttempts) {
      await prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: { status: "LOCKED" },
      });
      throw new Error("Too many verification attempts. Request a new code.");
    }

    if (challenge.codeHash !== codeHash) {
      const nextAttempts = challenge.attemptCount + 1;
      await prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: {
          attemptCount: nextAttempts,
          status: nextAttempts >= challenge.maxAttempts ? "LOCKED" : "PENDING",
        },
      });
      throw new Error("Invalid or expired verification code.");
    }

    await prisma.\$transaction([
      prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: {
          consumedAt: now,
          status: "VERIFIED",
        },
      }),
      prisma.user.update({
        where: { id: challenge.userId },
        data: { emailVerifiedAt: now },
      }),
    ]);

    return { ok: true, message: "Email verified successfully." };
  }

  async requestPasswordReset(emailInput: string) {
    const email = normalizeEmail(emailInput);

    const user = await prisma.user.findFirst({
      where: { email },
    });

    if (!user) {
      return { ok: true, message: "If an account exists, a reset email has been sent." };
    }

    await prisma.verificationChallenge.updateMany({
      where: {
        userId: user.id,
        channel: "EMAIL",
        purpose: "PASSWORD_RESET",
        status: "PENDING",
      },
      data: {
        status: "CANCELLED",
      },
    });

    const token = generateOpaqueToken();
    const destinationHash = hashForStorage(email);
    const codeHash = hashForStorage(token);

    const challenge = await prisma.verificationChallenge.create({
      data: {
        userId: user.id,
        channel: "EMAIL",
        purpose: "PASSWORD_RESET",
        destinationMasked: maskEmail(email),
        destinationHash,
        codeHash,
        expiresAt: addMinutes(notificationsConfig.resetLinkMinutes),
        maxAttempts: 5,
        status: "PENDING",
      },
    });

    const resetUrl = \`\${notificationsConfig.appBaseUrl}/reset-password?token=\${encodeURIComponent(token)}\`;

    await notificationService.sendPasswordResetEmail({
      userId: user.id,
      to: email,
      resetUrl,
    });

    return {
      ok: true,
      message: "If an account exists, a reset email has been sent.",
      challengeId: challenge.id,
    };
  }

  async resetPassword(tokenInput: string, password: string) {
    const codeHash = hashForStorage(tokenInput.trim());

    const challenge = await prisma.verificationChallenge.findFirst({
      where: {
        channel: "EMAIL",
        purpose: "PASSWORD_RESET",
        codeHash,
        status: "PENDING",
      },
      orderBy: { createdAt: "desc" },
    });

    if (!challenge) {
      throw new Error("Invalid or expired reset token.");
    }

    const now = new Date();

    if (challenge.expiresAt <= now) {
      await prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: { status: "EXPIRED" },
      });
      throw new Error("Invalid or expired reset token.");
    }

    const passwordHash = await argon2.hash(password);

    await prisma.\$transaction([
      prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: {
          consumedAt: now,
          status: "VERIFIED",
        },
      }),
      prisma.user.update({
        where: { id: challenge.userId },
        data: { ${PASSWORD_FIELD}: passwordHash },
      }),
    ]);

    return { ok: true, message: "Password reset successfully." };
  }
}

export const verificationService = new VerificationService();
EOF

echo "==> Writing verification routes ..."
cat > apps/api/src/modules/verification/verification.routes.ts <<'EOF'
import { Router } from "express";
import { verificationService } from "./verification.service";

const router = Router();

router.post("/auth/verify-email/request", async (req, res) => {
  try {
    const email = String(req.body?.email ?? "").trim();
    if (!email) {
      return res.status(400).json({
        error: { code: "EMAIL_REQUIRED", message: "Email is required." },
      });
    }

    const result = await verificationService.requestEmailVerification(email);
    return res.json(result);
  } catch (error: any) {
    return res.status(500).json({
      error: {
        code: "VERIFY_EMAIL_REQUEST_FAILED",
        message: error?.message ?? "Failed to request verification email.",
      },
    });
  }
});

router.post("/auth/verify-email/confirm", async (req, res) => {
  try {
    const email = String(req.body?.email ?? "").trim();
    const code = String(req.body?.code ?? "").trim();

    if (!email || !code) {
      return res.status(400).json({
        error: { code: "EMAIL_AND_CODE_REQUIRED", message: "Email and code are required." },
      });
    }

    const result = await verificationService.confirmEmailVerification(email, code);
    return res.json(result);
  } catch (error: any) {
    return res.status(400).json({
      error: {
        code: "VERIFY_EMAIL_CONFIRM_FAILED",
        message: error?.message ?? "Failed to verify email.",
      },
    });
  }
});

router.post("/auth/password/forgot", async (req, res) => {
  try {
    const email = String(req.body?.email ?? "").trim();
    if (!email) {
      return res.status(400).json({
        error: { code: "EMAIL_REQUIRED", message: "Email is required." },
      });
    }

    const result = await verificationService.requestPasswordReset(email);
    return res.json(result);
  } catch (error: any) {
    return res.status(500).json({
      error: {
        code: "PASSWORD_FORGOT_FAILED",
        message: error?.message ?? "Failed to request password reset.",
      },
    });
  }
});

router.post("/auth/password/reset", async (req, res) => {
  try {
    const token = String(req.body?.token ?? "").trim();
    const password = String(req.body?.password ?? "").trim();

    if (!token || !password) {
      return res.status(400).json({
        error: { code: "TOKEN_AND_PASSWORD_REQUIRED", message: "Token and password are required." },
      });
    }

    if (password.length < 10) {
      return res.status(400).json({
        error: {
          code: "PASSWORD_TOO_SHORT",
          message: "Password must be at least 10 characters.",
        },
      });
    }

    const result = await verificationService.resetPassword(token, password);
    return res.json(result);
  } catch (error: any) {
    return res.status(400).json({
      error: {
        code: "PASSWORD_RESET_FAILED",
        message: error?.message ?? "Failed to reset password.",
      },
    });
  }
});

export default router;
EOF

echo "==> Patching app.ts to mount verification routes ..."
python3 - <<'PY'
from pathlib import Path

p = Path("apps/api/src/app.ts")
text = p.read_text()

imp = 'import verificationRoutes from "./modules/verification/verification.routes";'
if imp not in text:
    lines = text.splitlines()
    insert_at = 0
    for i, ln in enumerate(lines):
        if ln.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, imp)
    text = "\n".join(lines)

if 'app.use("/api", verificationRoutes);' not in text:
    marker = "// Global error handler"
    block = """
app.use("/api", verificationRoutes);
app.use("/backend-api", verificationRoutes);
""".strip()
    if marker in text:
        text = text.replace(marker, block + "\n\n" + marker)
    else:
        text += "\n\n" + block + "\n"

p.write_text(text)
print("Patched apps/api/src/app.ts")
PY

echo "==> Best-effort onboarding patch for OTP / email verification ..."
python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/api/src/modules/onboarding/onboarding.service.ts")
if not p.exists():
    print("onboarding.service.ts not found; skipping.")
    raise SystemExit(0)

text = p.read_text()
original = text

# If user query uses select, include email/phone verification fields
if "emailVerifiedAt" not in text and "findUnique" in text and "select:" in text:
    text = re.sub(
        r"(select\s*:\s*\{)",
        r'\1\n        emailVerifiedAt: true,\n        phoneVerifiedAt: true,',
        text,
        count=1,
    )

# Replace existing otpVerified const if present
text2, n = re.subn(
    r"const\s+otpVerified\s*=\s*.*?;",
    'const otpVerified = Boolean((user as any)?.emailVerifiedAt || (user as any)?.phoneVerifiedAt);',
    text,
    count=1,
    flags=re.DOTALL,
)
text = text2

# If no const existed but OTP appears, inject helper before steps
if n == 0 and "OTP" in text and "const steps" in text and "otpVerified" not in text:
    text = text.replace(
        "const steps",
        'const otpVerified = Boolean((user as any)?.emailVerifiedAt || (user as any)?.phoneVerifiedAt);\n\n    const steps',
        1,
    )

if text != original:
    p.write_text(text)
    print("Patched onboarding.service.ts")
else:
    print("No onboarding OTP patch applied automatically. Review manually if needed.")
PY

echo "==> Scanning for dev verification exposure in frontend ..."
rg -n 'Development OTP code|Development reset link|developmentOtpCode|devOtp|devReset|reset link' apps/web > /tmp/phase12_verification_exposure_scan.txt || true
echo "Saved scan: /tmp/phase12_verification_exposure_scan.txt"

echo "==> Writing env example ..."
cat > scripts/phase12_email_env.example <<'EOF'
# Phase 1/2 email verification foundation
APP_BASE_URL=https://dcapitalx.com

# Email provider
EMAIL_PROVIDER=resend
RESEND_API_KEY=replace_me
EMAIL_FROM=DCapX <no-reply@dcapitalx.com>

# Secrets (later inject from Vault)
OTP_HMAC_SECRET=replace_me_with_long_random_secret
VERIFICATION_OTP_MINUTES=10
RESET_LINK_MINUTES=30
EOF

echo
echo "==> Installing deps ..."
pnpm install

echo
echo "==> Prisma format / validate ..."
pnpm --filter api prisma format
pnpm --filter api prisma validate

echo
echo "==> Type build check ..."
pnpm --filter api build

echo
echo "✅ Phase 1/2 email verification foundation pack applied."
echo
echo "NEXT:"
echo "  1) Review /tmp/phase12_verification_exposure_scan.txt"
echo "  2) Add env values from scripts/phase12_email_env.example"
echo "  3) Run migration:"
echo "       pnpm --filter api prisma migrate dev --name add_email_verification_foundation"
echo "       pnpm --filter api prisma generate"
echo "  4) Rebuild containers:"
echo "       docker compose build api web --no-cache"
echo "       docker compose up -d api web"
echo
echo "NEW ENDPOINTS:"
echo "  POST /api/auth/verify-email/request   { email }"
echo "  POST /api/auth/verify-email/confirm   { email, code }"
echo "  POST /api/auth/password/forgot        { email }"
echo "  POST /api/auth/password/reset         { token, password }"
echo
echo "VAULT-READY SECRETS:"
echo "  RESEND_API_KEY"
echo "  EMAIL_FROM"
echo "  OTP_HMAC_SECRET"
echo "  APP_BASE_URL"
