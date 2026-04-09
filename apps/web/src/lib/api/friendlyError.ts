export function friendlyPortalError(error: any, fallback: string): string {
  const code = error?.error?.code;
  const message =
    error?.error?.message ||
    error?.message ||
    "";

  if (code === "UNAUTHENTICATED" || /authentication required/i.test(message)) {
    return "Please sign in to continue.";
  }

  if (/failed to fetch/i.test(message)) {
    return "We couldn’t reach the server. Please make sure you are signed in and still connected to the Internet.";
  }

  return message || fallback;
}
