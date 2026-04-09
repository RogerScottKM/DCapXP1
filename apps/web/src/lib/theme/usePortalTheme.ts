import {
  usePortalPreferences,
  type PortalTheme,
  PortalPreferencesProvider,
} from "../preferences/PortalPreferencesProvider";

export type { PortalTheme };

export { PortalPreferencesProvider as PortalThemeProvider };

export function usePortalTheme() {
  const {
    theme,
    isDark,
    isLight,
    mounted,
    setTheme,
    toggleTheme,
  } = usePortalPreferences();

  return {
    theme,
    isDark,
    isLight,
    mounted,
    setTheme,
    toggleTheme,
  };
}
