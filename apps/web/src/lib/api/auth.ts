import { apiFetch } from "./client";

export interface LoginRequest {
  identifier: string;
  password: string;
}

export interface LoginResponse {
  ok: boolean;
  user: {
    id: string;
    email: string;
    username: string;
    status: string;
    profile: {
      firstName: string;
      lastName: string;
      country: string;
    } | null;
  };
  session: {
    id: string;
    expiresAtUtc: string;
  };
}

export interface SessionResponse {
  authenticated: boolean;
  user: {
    id: string;
    email: string;
    username: string;
    status: string;
    profile: {
      firstName: string;
      lastName: string;
      country: string;
    } | null;
    roles: Array<{
      roleCode: string;
      scopeType: string | null;
      scopeId: string | null;
    }>;
  };
  session: {
    id: string;
  };
}

export interface RequestPasswordResetRequest {
  email: string;
}

export interface RequestPasswordResetResponse {
  ok: boolean;
  message: string;
  devResetToken?: string;
  devResetUrl?: string;
  expiresAtUtc?: string;
}

// export string;
// }

export interface ResetPasswordRequest {
  token: string;
  newPassword: string;
}

export interface ResetPasswordResponse {
  ok: boolean;
  message: string;
}

export interface SendOtpRequest {
  channel: "EMAIL" | "SMS";
}

export interface SendOtpResponse {
  ok: boolean;
  message: string;
  channel: "EMAIL" | "SMS";
  destinationMasked: string;
  expiresAtUtc: string;
  devOtpCode?: string;
}

export interface VerifyOtpRequest {
  channel: "EMAIL" | "SMS";
  code: string;
}

export interface VerifyOtpResponse {
  ok: boolean;
  message: string;
  emailVerifiedAtUtc?: string | null;
  phoneVerifiedAtUtc?: string | null;
}

export function login(body: LoginRequest) {
  return apiFetch<LoginResponse>("/api/auth/login", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function getSession() {
  return apiFetch<SessionResponse>("/api/auth/session");
}

export function logout() {
  return apiFetch<{ ok: true }>("/api/auth/logout", {
    method: "POST",
  });
}

export function requestPasswordReset(body: RequestPasswordResetRequest) {
  return apiFetch<RequestPasswordResetResponse>("/api/auth/request-password-reset", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function resetPassword(body: ResetPasswordRequest) {
  return apiFetch<ResetPasswordResponse>("/api/auth/reset-password", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function sendOtp(body: SendOtpRequest) {
  return apiFetch<SendOtpResponse>("/api/auth/send-otp", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function verifyOtp(body: VerifyOtpRequest) {
  return apiFetch<VerifyOtpResponse>("/api/auth/verify-otp", {
    method: "POST",
    body: JSON.stringify(body),
  });
}
