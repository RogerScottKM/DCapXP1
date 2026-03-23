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
