import React, { useEffect, useState } from "react";
import { useRouter } from "next/router";
import { getSession, login } from "../../lib/api/auth";

export default function LoginPage() {
  const router = useRouter();

  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [isCheckingSession, setIsCheckingSession] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;

    async function checkSession() {
      try {
        await getSession();
        if (isMounted) {
          router.replace("/app/onboarding");
        }
      } catch {
        // Not logged in yet — stay on login page.
      } finally {
        if (isMounted) {
          setIsCheckingSession(false);
        }
      }
    }

    checkSession();

    return () => {
      isMounted = false;
    };
  }, [router]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await login({ identifier, password });

      router.push("/app/onboarding");
    } catch (error: any) {
      setErrorMessage(
        error?.error?.message ||
          error?.message ||
          "Login failed."
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  if (isCheckingSession) {
    return (
      <main style={{ maxWidth: 480, margin: "0 auto", padding: 24 }}>
        <h1>Login</h1>
        <p>Checking session...</p>
      </main>
    );
  }

  return (
    <main style={{ maxWidth: 480, margin: "0 auto", padding: 24 }}>
      <h1>Login</h1>
      <p>Sign in to continue to the DCapX onboarding portal.</p>

      {errorMessage ? (
        <div
          style={{
            border: "1px solid #f0b4b4",
            borderRadius: 8,
            padding: 16,
            marginBottom: 16,
          }}
        >
          <strong>Error:</strong> {errorMessage}
        </div>
      ) : null}

      <form onSubmit={handleSubmit} style={{ display: "grid", gap: 16 }}>
        <div>
          <label htmlFor="identifier">Email or Username</label>
          <input
            id="identifier"
            type="text"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            placeholder="pedro.vx.km@gmail.com"
            autoComplete="username"
            style={{ width: "100%", padding: 10, marginTop: 6 }}
          />
        </div>

        <div>
          <label htmlFor="password">Password</label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Enter your password"
            autoComplete="current-password"
            style={{ width: "100%", padding: 10, marginTop: 6 }}
          />
        </div>

        <button
          type="submit"
          disabled={isSubmitting || !identifier || !password}
          style={{
            padding: "10px 16px",
            borderRadius: 8,
            border: "1px solid #222",
            cursor:
              isSubmitting || !identifier || !password
                ? "not-allowed"
                : "pointer",
          }}
        >
          {isSubmitting ? "Signing in..." : "Sign In"}
        </button>
      </form>
    </main>
  );
}
