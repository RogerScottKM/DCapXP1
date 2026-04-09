import React, {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type PortalTheme = "dark" | "light";

export const PORTAL_LANGUAGES = [
  { code: "en", label: "English" },
  { code: "vi", label: "Tiếng Việt" },
  { code: "zh-CN", label: "简体中文" },
  { code: "zh-TW", label: "繁體中文" },
  { code: "es", label: "Español" },
  { code: "fr", label: "Français" },
  { code: "ar", label: "العربية" },
  { code: "pt", label: "Português" },
  { code: "hi", label: "हिन्दी" },
  { code: "ja", label: "日本語" },
] as const;

export type PortalLanguageCode = (typeof PORTAL_LANGUAGES)[number]["code"];

type PortalPreferencesContextValue = {
  theme: PortalTheme;
  isDark: boolean;
  isLight: boolean;
  language: PortalLanguageCode;
  mounted: boolean;
  setTheme: (theme: PortalTheme) => void;
  toggleTheme: () => void;
  setLanguage: (language: PortalLanguageCode) => void;
};

const THEME_KEY = "dcapx-theme";
const LANGUAGE_KEY = "dcapx-language";

const PortalPreferencesContext =
  createContext<PortalPreferencesContextValue | null>(null);

export function PortalPreferencesProvider(props: { children: ReactNode }) {
  const [theme, setTheme] = useState<PortalTheme>("dark");
  const [language, setLanguage] = useState<PortalLanguageCode>("en");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    try {
      const storedTheme =
        typeof window !== "undefined" ? window.localStorage.getItem(THEME_KEY) : null;
      const storedLanguage =
        typeof window !== "undefined" ? window.localStorage.getItem(LANGUAGE_KEY) : null;

      if (storedTheme === "dark" || storedTheme === "light") {
        setTheme(storedTheme);
      } else {
        const prefersDark =
          typeof window !== "undefined" &&
          typeof window.matchMedia === "function" &&
          window.matchMedia("(prefers-color-scheme: dark)").matches;
        setTheme(prefersDark ? "dark" : "light");
      }

      if (
        storedLanguage &&
        PORTAL_LANGUAGES.some((item) => item.code === storedLanguage)
      ) {
        setLanguage(storedLanguage as PortalLanguageCode);
      }
    } finally {
      setMounted(true);
    }
  }, []);

  useEffect(() => {
    if (!mounted || typeof document === "undefined") return;

    document.documentElement.dataset.dcapxTheme = theme;
    document.documentElement.dataset.dcapxLanguage = language;

    document.documentElement.classList.remove("dcapx-dark", "dcapx-light");
    document.documentElement.classList.add(
      theme === "dark" ? "dcapx-dark" : "dcapx-light"
    );

    document.body.style.backgroundColor =
      theme === "dark" ? "#020817" : "#e5e7eb";
    document.body.style.color = theme === "dark" ? "#ffffff" : "#0f172a";

    if (typeof window !== "undefined") {
      window.localStorage.setItem(THEME_KEY, theme);
      window.localStorage.setItem(LANGUAGE_KEY, language);
    }
  }, [theme, language, mounted]);

  const value = useMemo<PortalPreferencesContextValue>(
    () => ({
      theme,
      isDark: theme === "dark",
      isLight: theme === "light",
      language,
      mounted,
      setTheme,
      toggleTheme: () =>
        setTheme((prev) => (prev === "dark" ? "light" : "dark")),
      setLanguage,
    }),
    [theme, language, mounted]
  );

  return (
    <PortalPreferencesContext.Provider value={value}>
      {props.children}
    </PortalPreferencesContext.Provider>
  );
}

export function usePortalPreferences() {
  const context = useContext(PortalPreferencesContext);

  if (!context) {
    throw new Error(
      "usePortalPreferences must be used within PortalPreferencesProvider"
    );
  }

  return context;
}
