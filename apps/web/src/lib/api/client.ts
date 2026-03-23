import type { ApiErrorResponse } from "@dcapx/contracts";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, "") || "";

export async function apiFetch<T>(input: string, init?: RequestInit): Promise<T> {
  const url = `${API_BASE_URL}${input}`;

  const response = await fetch(url, {
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
    ...init,
  });

  if (!response.ok) {
    const error = (await response.json()) as ApiErrorResponse;
    throw error;
  }

  return response.json() as Promise<T>;
}
