import React from "react";
import Link from "next/link";
import ThemeToggle from "./ThemeToggle";
import LogoutButton from "./LogoutButton";

type Props = {
  title: string;
  description?: string;
  children: React.ReactNode;
};

export default function PortalShell({ title, description, children }: Props) {
  return (
    <main className="min-h-screen bg-white text-slate-900 dark:bg-slate-950 dark:text-slate-100">
      <div className="mx-auto flex min-h-screen max-w-7xl flex-col px-6 py-8">
        <header className="flex flex-col gap-4 border-b border-slate-200 pb-5 dark:border-slate-800 md:flex-row md:items-center md:justify-between">
          <div className="flex items-center gap-8">
            <Link href="/" className="text-2xl font-semibold tracking-tight">
              DCapX
            </Link>

            <nav className="hidden gap-6 text-sm text-slate-600 dark:text-slate-300 md:flex">
              <Link href="/app/onboarding" className="transition hover:text-slate-900 dark:hover:text-white">
                Onboarding
              </Link>
              <Link href="/app/consents" className="transition hover:text-slate-900 dark:hover:text-white">
                Consents
              </Link>
              <Link href="/app/kyc" className="transition hover:text-slate-900 dark:hover:text-white">
                KYC
              </Link>
            </nav>
          </div>

          <div className="flex items-center gap-3">
            <ThemeToggle />
            <LogoutButton />
          </div>
        </header>

        <section className="mx-auto w-full max-w-5xl py-10">
          <div className="mb-8">
            <h1 className="text-3xl font-semibold tracking-tight">{title}</h1>
            {description ? (
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-600 dark:text-slate-400">
                {description}
              </p>
            ) : null}
          </div>

          {children}
        </section>
      </div>
    </main>
  );
}
