import { usePortalPreferences } from "../../lib/preferences/PortalPreferencesProvider";

export default function ThemeToggle() {
  const { isDark, toggleTheme, mounted } = usePortalPreferences();

  return (
    <button
      type="button"
      onClick={toggleTheme}
      className={[
        "inline-flex items-center gap-2 rounded-full border px-4 py-2 text-base font-semibold transition",
        isDark
          ? "border-white/10 bg-white/[0.04] text-slate-100 hover:bg-white/[0.07]"
          : "border-slate-300 bg-white text-slate-900 hover:bg-slate-50",
      ].join(" ")}
      aria-label="Toggle theme"
      title="Toggle theme"
    >
      <span>{isDark ? "🌙" : "☀️"}</span>
      <span>{mounted ? (isDark ? "Dark" : "Light") : "Theme"}</span>
    </button>
  );
}
