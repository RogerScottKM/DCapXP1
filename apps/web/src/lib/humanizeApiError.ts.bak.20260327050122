function tryParseJsonString(input: string): unknown {
  try {
    return JSON.parse(input);
  } catch {
    return input;
  }
}

function flattenValidationMessage(input: unknown): string | null {
  if (typeof input === "string") {
    const parsed = tryParseJsonString(input);
    if (parsed !== input) return flattenValidationMessage(parsed);
    return input;
  }

  if (Array.isArray(input)) {
    const countryIssue = input.find(
      (item: any) =>
        item &&
        Array.isArray(item.path) &&
        item.path.includes("country")
    ) as any;

    if (countryIssue) {
      return "Please choose your country from the dropdown list.";
    }

    const firstMessage = input.find((item: any) => item?.message)?.message;
    if (typeof firstMessage === "string") {
      return firstMessage;
    }

    return null;
  }

  if (input && typeof input === "object") {
    const obj = input as Record<string, unknown>;

    if (typeof obj.message === "string") {
      const nested = flattenValidationMessage(obj.message);
      return nested ?? obj.message;
    }

    if (obj.error) {
      return flattenValidationMessage(obj.error);
    }
  }

  return null;
}

export function humanizeApiError(error: unknown): string {
  const fallback = "Something went wrong. Please try again.";

  if (!error) return fallback;

  if (typeof error === "string") {
    const lower = error.toLowerCase();

    if (lower.includes("network") || lower.includes("failed to fetch")) {
      return "We couldn’t reach the server. Please check your connection and try again.";
    }

    if (lower.includes("invalid or expired verification code")) {
      return "That verification code is invalid or has expired. Please request a new one.";
    }

    if (lower.includes("invalid or expired reset token")) {
      return "That password reset link is invalid or has expired. Please request a new one.";
    }

    const parsed = flattenValidationMessage(error);
    if (parsed) {
      if (parsed.toLowerCase().includes("too big") && parsed.toLowerCase().includes("country")) {
        return "Please choose your country from the dropdown list.";
      }
      return parsed;
    }

    return error;
  }

  const anyErr = error as any;

  const code = anyErr?.error?.code ?? anyErr?.code;
  const message = anyErr?.error?.message ?? anyErr?.message;

  if (code === "EMAIL_ALREADY_EXISTS") {
    return "That email address is already registered. Try signing in or resetting your password.";
  }

  if (code === "USERNAME_ALREADY_EXISTS") {
    return "That username is already taken. Please choose another one.";
  }

  if (code === "VERIFY_EMAIL_CONFIRM_FAILED") {
    return "That verification code is invalid or has expired. Please request a new one.";
  }

  if (code === "PASSWORD_RESET_FAILED") {
    return "That password reset link is invalid or has expired. Please request a new one.";
  }

  if (code === "PASSWORD_TOO_SHORT") {
    return "Please choose a stronger password with at least 10 characters.";
  }

  if (typeof message === "string") {
    const lower = message.toLowerCase();

    if (lower.includes("invalid or expired verification code")) {
      return "That verification code is invalid or has expired. Please request a new one.";
    }

    if (lower.includes("too many verification attempts")) {
      return "Too many failed attempts. Please request a new verification code.";
    }

    if (lower.includes("invalid or expired reset token")) {
      return "That password reset link is invalid or has expired. Please request a new one.";
    }

    const parsed = flattenValidationMessage(message);
    if (parsed) {
      if (parsed.toLowerCase().includes("too big") && parsed.toLowerCase().includes("country")) {
        return "Please choose your country from the dropdown list.";
      }
      return parsed;
    }
  }

  const flattened = flattenValidationMessage(error);
  if (flattened) {
    if (flattened.toLowerCase().includes("too big") && flattened.toLowerCase().includes("country")) {
      return "Please choose your country from the dropdown list.";
    }
    return flattened;
  }

  return fallback;
}
