#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

mkdir -p apps/web/src/lib/theme
mkdir -p apps/web/pages

backup apps/web/src/lib/theme/usePortalTheme.ts
backup apps/web/pages/_app.tsx

echo "==> Writing shared theme provider ..."
cat > apps/web/src/lib/theme/usePortalTheme.ts <<'EOF'
import React, {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type PortalTheme = "dark" | "light";

type PortalThemeContextValue = {
  theme: PortalTheme;
  isDark: boolean;
  isLight: boolean;
  mounted: boolean;
  setTheme: (theme: PortalTheme) => void;
  toggleTheme: () => void;
};

const STORAGE_KEY = "dcapx-theme";

const PortalThemeContext = createContext<PortalThemeContextValue | undefined>(
  undefined
);

export function PortalThemeProvider(props: { children: ReactNode }) {
  const [theme, setTheme] = useState<PortalTheme>("dark");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    try {
      const stored =
        typeof window !== "undefined"
          ? window.localStorage.getItem(STORAGE_KEY)
          : null;

      if (stored === "dark" || stored === "light") {
        setTheme(stored);
      } else {
        const prefersDark =
          typeof window !== "undefined" &&
          typeof window.matchMedia === "function" &&
          window.matchMedia("(prefers-color-scheme: dark)").matches;

        setTheme(prefersDark ? "dark" : "light");
      }
    } finally {
      setMounted(true);
    }
  }, []);

  useEffect(() => {
    if (!mounted || typeof document === "undefined") return;

    document.documentElement.dataset.dcapxTheme = theme;
    document.documentElement.classList.remove("dcapx-dark", "dcapx-light");
    document.documentElement.classList.add(
      theme === "dark" ? "dcapx-dark" : "dcapx-light"
    );

    document.body.style.backgroundColor =
      theme === "dark" ? "#020817" : "#f1f5f9";
    document.body.style.color = theme === "dark" ? "#ffffff" : "#0f172a";

    if (typeof window !== "undefined") {
      window.localStorage.setItem(STORAGE_KEY, theme);
    }
  }, [theme, mounted]);

  const value = useMemo<PortalThemeContextValue>(
    () => ({
      theme,
      isDark: theme === "dark",
      isLight: theme === "light",
      mounted,
      setTheme,
      toggleTheme: () =>
        setTheme((prev) => (prev === "dark" ? "light" : "dark")),
    }),
    [theme, mounted]
  );

  return (
    <PortalThemeContext.Provider value={value}>
      {props.children}
    </PortalThemeContext.Provider>
  );
}

export function usePortalTheme() {
  const context = useContext(PortalThemeContext);

  if (!context) {
    throw new Error("usePortalTheme must be used within PortalThemeProvider");
  }

  return context;
}
EOF

echo "==> Writing /pages/_app.tsx ..."
cat > apps/web/pages/_app.tsx <<'EOF'
import type { AppProps } from "next/app";
import { PortalThemeProvider } from "../src/lib/theme/usePortalTheme";

export default function App({ Component, pageProps }: AppProps) {
  return (
    <PortalThemeProvider>
      <Component {...pageProps} />
    </PortalThemeProvider>
  );
}
EOF

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Shared theme provider applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
