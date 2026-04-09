type JsonValue = any;

async function requestJson(
  endpoint: string,
  init: RequestInit
): Promise<JsonValue> {
  const res = await fetch(endpoint, {
    ...init,
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });

  const raw = await res.text();
  let data: JsonValue = null;

  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = raw;
  }

  if (!res.ok) {
    throw data ?? { message: `Request failed with status ${res.status}.` };
  }

  return data;
}

async function tryApi(init: RequestInit, path: string): Promise<JsonValue> {
  const endpoints = [`/backend-api${path}`, `/api${path}`];
  let lastError: unknown = null;

  for (const endpoint of endpoints) {
    try {
      return await requestJson(endpoint, init);
    } catch (error: any) {
      lastError = error;
      const message = typeof error === "string" ? error : error?.message ?? error?.error?.message;
      if (String(message ?? "").includes("404")) continue;
      if (error?.error?.code === "NOT_FOUND") continue;
      if (typeof error === "string" && error.includes("Request failed with status 404")) continue;
      if (error?.message === `Request failed with status 404.`) continue;
      throw error;
    }
  }

  throw lastError ?? new Error("Endpoint not found.");
}

export async function requestEmailVerification(email: string) {
  return tryApi(
    {
      method: "POST",
      body: JSON.stringify({ email }),
    },
    "/auth/verify-email/request"
  );
}

export async function confirmEmailVerification(email: string, code: string) {
  return tryApi(
    {
      method: "POST",
      body: JSON.stringify({ email, code }),
    },
    "/auth/verify-email/confirm"
  );
}

export async function requestPasswordReset(email: string) {
  return tryApi(
    {
      method: "POST",
      body: JSON.stringify({ email }),
    },
    "/auth/password/forgot"
  );
}

export async function resetPassword(token: string, password: string) {
  return tryApi(
    {
      method: "POST",
      body: JSON.stringify({ token, password }),
    },
    "/auth/password/reset"
  );
}

export async function fetchSession() {
  const endpoints = ["/backend-api/auth/session", "/api/auth/session"];
  let lastError: unknown = null;

  for (const endpoint of endpoints) {
    try {
      return await requestJson(endpoint, {
        method: "GET",
      });
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError ?? new Error("Unable to load session.");
}
