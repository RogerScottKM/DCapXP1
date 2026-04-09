import { apiFetch } from "./client";

export interface RegisterClientRequest {
  email: string;
  username: string;
  firstName: string;
  lastName: string;
  phone: string;
  country: string;
}

export interface RegisterClientResponse {
  ok: true;
  user: {
    id: string;
    email: string;
    username: string;
  };
}

export function registerClient(body: RegisterClientRequest) {
  return apiFetch<RegisterClientResponse>("/api/auth/register", {
    method: "POST",
    body: JSON.stringify(body),
  });
}
