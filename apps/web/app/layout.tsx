// apps/web/app/layout.tsx
import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";
import ThemeToggle from "@/components/ThemeToggle";
import Providers from "./Providers";

export const metadata: Metadata = {
  title: "DCapX — Agent-Native Exchange",
  description:
    "Agent-native exchange and deterministic settlement rails for autonomous AI agents. Built by DCapital Global.",
  metadataBase: new URL("https://dcapital.global"),
  openGraph: {
    title: "DCapX — Agent-Native Exchange",
    description: "Deterministic, auditable settlement. Exchange built for AI agents.",
    url: "https://dcapital.global",
    siteName: "DCapX",
    type: "website",
  },
  robots: { index: true, follow: true },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full">
      <body className="min-h-full bg-white text-slate-900 dark:bg-slate-950 dark:text-slate-100">
      <Providers>
        <header className="sticky top-0 z-50 border-b border-slate-200/70 bg-white/75 backdrop-blur dark:border-slate-800/60 dark:bg-slate-950/70">
          <nav className="mx-auto flex h-14 max-w-6xl items-center gap-6 px-6">
            <Link href="/" className="font-semibold tracking-tight">
              DCapX
            </Link>

            <div className="ml-auto flex items-center gap-4 text-slate-600 dark:text-slate-300">
              <Link className="hover:text-slate-900 dark:hover:text-white" href="/foundation">
                Foundation
              </Link>
              <Link className="hover:text-slate-900 dark:hover:text-white" href="/agent-advisory">
                Agent Advisory
              </Link>
              <a className="hover:text-slate-900 dark:hover:text-white" href="/api/health">
                /api/health
              </a>
              <Link className="hover:text-slate-900 dark:hover:text-white" href="/dashboard">
                Dashboard
              </Link>
              <Link className="hover:text-slate-900 dark:hover:text-white" href="/markets/BTC-USD">
                Exchange
              </Link>
              <Link className="hover:text-slate-900 dark:hover:text-white" href="/portfolio">
                Portfolio
              </Link>
              <Link className="hover:text-slate-900 dark:hover:text-white" href="/account">
                Account
              </Link>

              <ThemeToggle />
            </div>
          </nav>
        </header>

        <main>{children}</main>

        <footer className="mt-20 border-t border-slate-200/70 dark:border-slate-800/60">
          <div className="mx-auto max-w-6xl px-6 py-10 text-sm text-slate-500 dark:text-slate-400">
            © {new Date().getFullYear()} DCapital Global. All rights reserved.
          </div>
        </footer>
      </Providers>
    </body>
    </html>
  );
}
