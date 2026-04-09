import {
  PORTAL_LANGUAGES,
  usePortalPreferences,
} from "../../lib/preferences/PortalPreferencesProvider";

export default function LanguageSelect() {
  const { language, setLanguage, isDark } = usePortalPreferences();

  return (
    <label
      className={[
        "inline-flex items-center gap-2 rounded-full border px-3 py-2 text-sm font-semibold transition",
        isDark
          ? "border-white/10 bg-white/[0.04] text-slate-100"
          : "border-slate-300 bg-white text-slate-900",
      ].join(" ")}
    >
      <span>🌐</span>
      <select
        value={language}
        onChange={(e) => setLanguage(e.target.value as any)}
        className={[
          "bg-transparent outline-none",
          isDark ? "text-slate-100" : "text-slate-900",
        ].join(" ")}
        aria-label="Select language"
      >
        {PORTAL_LANGUAGES.map((item) => (
          <option key={item.code} value={item.code}>
            {item.label}
          </option>
        ))}
      </select>
    </label>
  );
}
