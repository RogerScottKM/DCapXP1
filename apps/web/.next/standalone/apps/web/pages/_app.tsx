import type { AppProps } from "next/app";
import { PortalPreferencesProvider } from "../src/lib/preferences/PortalPreferencesProvider";

export default function App({ Component, pageProps }: AppProps) {
  return (
    <PortalPreferencesProvider>
      <Component {...pageProps} />
      <style jsx global>{`
        html[data-dcapx-theme="light"] body {
          background: #e5e7eb;
          color: #0f172a;
        }

        html[data-dcapx-theme="light"] table th,
        html[data-dcapx-theme="light"] table td,
        html[data-dcapx-theme="light"] table th *,
        html[data-dcapx-theme="light"] table td * {
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] table th {
          color: #475569 !important;
        }

        html[data-dcapx-theme="light"] table td {
          color: #0f172a !important;
        }

        html[data-dcapx-theme="light"] .text-slate-300,
        html[data-dcapx-theme="light"] .text-slate-400,
        html[data-dcapx-theme="light"] .text-slate-500,
        html[data-dcapx-theme="light"] .text-slate-600,
        html[data-dcapx-theme="light"] .text-white\\/10,
        html[data-dcapx-theme="light"] .text-white\\/20,
        html[data-dcapx-theme="light"] .text-white\\/30,
        html[data-dcapx-theme="light"] .text-white\\/40,
        html[data-dcapx-theme="light"] .text-white\\/50,
        html[data-dcapx-theme="light"] .text-white\\/60,
        html[data-dcapx-theme="light"] .text-white\\/70,
        html[data-dcapx-theme="light"] .text-white\\/80 {
          color: #334155 !important;
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] .opacity-10,
        html[data-dcapx-theme="light"] .opacity-20,
        html[data-dcapx-theme="light"] .opacity-25,
        html[data-dcapx-theme="light"] .opacity-30,
        html[data-dcapx-theme="light"] .opacity-40,
        html[data-dcapx-theme="light"] .opacity-50,
        html[data-dcapx-theme="light"] .opacity-60,
        html[data-dcapx-theme="light"] .opacity-70,
        html[data-dcapx-theme="light"] .opacity-75,
        html[data-dcapx-theme="light"] .opacity-80 {
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] button,
        html[data-dcapx-theme="light"] [role="button"] {
          color: #0f172a;
        }

        html[data-dcapx-theme="light"] button *,
        html[data-dcapx-theme="light"] [role="button"] * {
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] .text-emerald-300,
        html[data-dcapx-theme="light"] .text-emerald-400,
        html[data-dcapx-theme="light"] .text-green-400 {
          color: #047857 !important;
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] .text-rose-300,
        html[data-dcapx-theme="light"] .text-rose-400,
        html[data-dcapx-theme="light"] .text-red-400 {
          color: #be123c !important;
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] input,
        html[data-dcapx-theme="light"] select,
        html[data-dcapx-theme="light"] textarea {
          color: #0f172a !important;
        }
      `}</style>
    </PortalPreferencesProvider>
  );
}
