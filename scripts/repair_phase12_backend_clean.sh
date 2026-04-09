#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

mkdir -p apps/api/src/modules/notifications/providers
mkdir -p apps/api/src/modules/verification

backup apps/api/src/modules/notifications/notification.service.ts
backup apps/api/src/modules/verification/verification.service.ts
backup apps/api/src/modules/verification/verification.routes.ts

PASSWORD_FIELD="$(python3 - <<'PY'
from pathlib import Path
import re

text = Path("apps/api/prisma/schema.prisma").read_text()
m = re.search(r'model\s+User\s*\{(?P<body>.*?)\n\}', text, re.S)
body = m.group("body") if m else ""
if re.search(r'^\s*hashedPassword\b', body, re.M):
    print("hashedPassword")
else:
    print("passwordHash")
PY
)"

CONTACT_PURPOSE="$(python3 - <<'PY'
from pathlib import Path
text = Path("apps/api/prisma/schema.prisma").read_text()
if "CONTACT_VERIFICATION" in text:
    print("CONTACT_VERIFICATION")
else:
    print("CONTACT_VERIFY")
PY
)"

echo "Using password field: ${PASSWORD_FIELD}"
echo "Using contact verification enum: ${CONTACT_PURPOSE}"

echo "==> Rewriting notification.service.ts ..."
cat > apps/api/src/modules/notifications/notification.service.ts <<'EOF'
import { prisma } from "../../lib/prisma";
import { notificationsConfig } from "./notifications.config";
import type { EmailProvider } from "./notifications.types";
import { ConsoleEmailProvider } from "./providers/console-email.provider";
import { ResendEmailProvider } from "./providers/resend-email.provider";

function maskEmail(email: string): string {
  const [local, domain] = email.trim().toLowerCase().split("@");
  if (!local || !domain) return email;
  const shown = local.length <= 2 ? (local[0] ?? "*") : `${local.slice(0, 2)}***`;
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

    let provider: string = String(notificationsConfig.emailProvider);
    let providerMessageId: string | null = null;
    let status = "SENT";
    let errorCode: string | null = null;
    let errorMessage: string | null = null;

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

    let provider: string = String(notificationsConfig.emailProvider);
    let providerMessageId: string | null = null;
    let status = "SENT";
    let errorCode: string | null = null;
    let errorMessage: string | null = null;

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
        },
      });
    }
  }
}

export const notificationService = new NotificationService();
EOF

echo "==> Rewriting verification.service.ts ..."
cat > apps/api/src/modules/verification/verification.service.ts <<EOF
import * as argon2 from "argon2";
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

const CONTACT_VERIFICATION_PURPOSE = "${CONTACT_PURPOSE}" as const;

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
        purpose: CONTACT_VERIFICATION_PURPOSE,
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
        purpose: CONTACT_VERIFICATION_PURPOSE,
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
        purpose: CONTACT_VERIFICATION_PURPOSE,
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

    const newPasswordHash = await argon2.hash(password);

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
        data: { ${PASSWORD_FIELD}: newPasswordHash },
      }),
    ]);

    return { ok: true, message: "Password reset successfully." };
  }
}

export const verificationService = new VerificationService();
EOF

echo "==> Rewriting verification.routes.ts ..."
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

echo
echo "==> Build check ..."
pnpm --filter api build

echo
echo "✅ Backend repair pack applied."
echo
echo "Next:"
echo "  pnpm --filter api prisma generate"
echo "  docker compose build api web --no-cache"
echo "  docker compose up -d api web"
