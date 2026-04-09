const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, "") || "";

function resolveUrl(input: string): string {
  if (input.startsWith("http")) return input;

  if (!API_BASE) return input;

  if (input.startsWith("/api/")) {
    return `${API_BASE}${input.slice(4)}`;
  }

  return `${API_BASE}${input}`;
}

export async function apiFetch<T>(input: string, init?: RequestInit): Promise<T> {
  const url = resolveUrl(input);

  const response = await fetch(url, {
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
    ...init,
  });

  let parsed: any = null;

  try {
    parsed = await response.json();
  } catch {
    parsed = null;
  }

  if (!response.ok) {
    throw (
      parsed || {
        error: {
          code: "HTTP_ERROR",
          message: `Request failed with status ${response.status}.`,
        },
      }
    );
  }

  return parsed as T;
}
