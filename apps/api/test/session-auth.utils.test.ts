import { afterEach, describe, expect, it, vi } from "vitest";

import {
  SESSION_COOKIE_NAME,
  buildSessionCookieValue,
  clearSessionCookie,
  createSessionSecret,
  getCookieFromRequest,
  getSessionExpiryDate,
  hashSessionSecret,
  parseSessionCookieValue,
  setSessionCookie,
  verifySessionSecret,
} from "../src/lib/session-auth";

const ORIGINAL_ENV = { ...process.env };

function restoreEnv() {
  for (const key of Object.keys(process.env)) {
    if (!(key in ORIGINAL_ENV)) {
      delete process.env[key];
    }
  }
  Object.assign(process.env, ORIGINAL_ENV);
}

afterEach(() => {
  restoreEnv();
  vi.restoreAllMocks();
});

describe("session-auth utilities", () => {
  describe("createSessionSecret", () => {
    it("generates a 64-character hex string", () => {
      const secret = createSessionSecret();
      expect(secret).toMatch(/^[0-9a-f]{64}$/);
    });

    it("generates unique secrets", () => {
      const a = createSessionSecret();
      const b = createSessionSecret();
      expect(a).not.toBe(b);
    });
  });

  describe("hashSessionSecret / verifySessionSecret", () => {
    it("hashes and verifies a session secret round-trip", async () => {
      const secret = createSessionSecret();
      const hash = await hashSessionSecret(secret);

      expect(typeof hash).toBe("string");
      expect(hash.length).toBeGreaterThan(20);
      await expect(verifySessionSecret(hash, secret)).resolves.toBe(true);
    });

    it("returns false for a wrong session secret", async () => {
      const secret = createSessionSecret();
      const wrong = createSessionSecret();
      const hash = await hashSessionSecret(secret);

      await expect(verifySessionSecret(hash, wrong)).resolves.toBe(false);
    });
  });

  describe("buildSessionCookieValue / parseSessionCookieValue", () => {
    it("round-trips sessionId and secret", () => {
      const cookie = buildSessionCookieValue("sess-123", "secret-abc");
      const parsed = parseSessionCookieValue(cookie);

      expect(parsed).toEqual({
        sessionId: "sess-123",
        secret: "secret-abc",
      });
    });

    it("handles sessionId containing no dots", () => {
      const cookie = buildSessionCookieValue("clxxxxxxxxxx", "hex64chars");
      const parsed = parseSessionCookieValue(cookie);

      expect(parsed).toEqual({
        sessionId: "clxxxxxxxxxx",
        secret: "hex64chars",
      });
    });

    it("preserves secret remainder after first dot", () => {
      const parsed = parseSessionCookieValue("sess-123.secret.with.extra.dots");

      expect(parsed).toEqual({
        sessionId: "sess-123",
        secret: "secret.with.extra.dots",
      });
    });

    it("returns null for undefined input", () => {
      expect(parseSessionCookieValue(undefined)).toBeNull();
    });

    it("returns null for null input", () => {
      expect(parseSessionCookieValue(null)).toBeNull();
    });

    it("returns null for empty string", () => {
      expect(parseSessionCookieValue("")).toBeNull();
    });

    it("returns null for value with no dot", () => {
      expect(parseSessionCookieValue("noseparator")).toBeNull();
    });

    it("returns null when sessionId part is empty", () => {
      expect(parseSessionCookieValue(".secret")).toBeNull();
    });

    it("returns null when secret part is empty", () => {
      expect(parseSessionCookieValue("sess-123.")).toBeNull();
    });
  });

  describe("getSessionExpiryDate", () => {
    it("returns a date about 30 days in the future", () => {
      const expiry = getSessionExpiryDate();
      const diffMs = expiry.getTime() - Date.now();
      const diffDays = diffMs / (1000 * 60 * 60 * 24);

      expect(diffDays).toBeGreaterThan(29);
      expect(diffDays).toBeLessThan(31);
    });
  });

  describe("getCookieFromRequest", () => {
    it("extracts named cookie from header", () => {
      const req = {
        headers: { cookie: "dcapx_session=value123; other=xyz" },
      } as any;

      expect(getCookieFromRequest(req, "dcapx_session")).toBe("value123");
    });

    it("ignores partial-name cookie collisions", () => {
      const req = {
        headers: { cookie: "dcapx_session_backup=wrong; dcapx_session=right-value; other=xyz" },
      } as any;

      expect(getCookieFromRequest(req, "dcapx_session")).toBe("right-value");
    });

    it("returns null when cookie is not present", () => {
      const req = {
        headers: { cookie: "other=xyz" },
      } as any;

      expect(getCookieFromRequest(req, "dcapx_session")).toBeNull();
    });

    it("returns null when no cookie header exists", () => {
      const req = { headers: {} } as any;

      expect(getCookieFromRequest(req, "dcapx_session")).toBeNull();
    });

    it("handles URL-encoded cookie values", () => {
      const req = {
        headers: { cookie: "dcapx_session=sess-1%2Esecret" },
      } as any;

      expect(getCookieFromRequest(req, "dcapx_session")).toBe("sess-1.secret");
    });

    it("handles surrounding whitespace in cookie header", () => {
      const req = {
        headers: { cookie: "  other=xyz  ;   dcapx_session=sess-2.secret-2   " },
      } as any;

      expect(getCookieFromRequest(req, "dcapx_session")).toBe("sess-2.secret-2");
    });
  });

  describe("setSessionCookie", () => {
    it("sets default HttpOnly Path SameSite and expiry attributes", () => {
      delete process.env.NODE_ENV;
      delete process.env.SESSION_COOKIE_SAMESITE;

      const res = { setHeader: vi.fn() } as any;
      const expiresAt = new Date(Date.now() + 60_000);

      setSessionCookie(res, "sess-1.secret-abc", expiresAt);

      expect(res.setHeader).toHaveBeenCalledTimes(1);
      const [headerName, headerValue] = res.setHeader.mock.calls[0];

      expect(headerName).toBe("Set-Cookie");
      expect(headerValue).toContain(`${SESSION_COOKIE_NAME}=sess-1.secret-abc`);
      expect(headerValue).toContain("Path=/");
      expect(headerValue).toContain("HttpOnly");
      expect(headerValue).toContain("SameSite=Lax");
      expect(headerValue).toContain("Max-Age=");
      expect(headerValue).toContain("Expires=");
      expect(headerValue).not.toContain("Secure;");
    });

    it("adds Secure in production and respects SESSION_COOKIE_SAMESITE", () => {
      process.env.NODE_ENV = "production";
      process.env.SESSION_COOKIE_SAMESITE = "None";

      const res = { setHeader: vi.fn() } as any;
      const expiresAt = new Date(Date.now() + 60_000);

      setSessionCookie(res, "sess-2.secret-xyz", expiresAt);

      const [, headerValue] = res.setHeader.mock.calls[0];
      expect(headerValue).toContain(`${SESSION_COOKIE_NAME}=sess-2.secret-xyz`);
      expect(headerValue).toContain("Path=/");
      expect(headerValue).toContain("HttpOnly");
      expect(headerValue).toContain("SameSite=None");
      expect(headerValue).toContain("Secure;");
    });
  });

  describe("clearSessionCookie", () => {
    it("clears the session cookie with immediate expiry", () => {
      delete process.env.NODE_ENV;
      delete process.env.SESSION_COOKIE_SAMESITE;

      const res = { setHeader: vi.fn() } as any;

      clearSessionCookie(res);

      expect(res.setHeader).toHaveBeenCalledTimes(1);
      const [headerName, headerValue] = res.setHeader.mock.calls[0];

      expect(headerName).toBe("Set-Cookie");
      expect(headerValue).toContain(`${SESSION_COOKIE_NAME}=;`);
      expect(headerValue).toContain("Path=/");
      expect(headerValue).toContain("HttpOnly");
      expect(headerValue).toContain("SameSite=Lax");
      expect(headerValue).toContain("Max-Age=0");
      expect(headerValue).toContain("Expires=Thu, 01 Jan 1970 00:00:00 GMT");
    });
  });
});
