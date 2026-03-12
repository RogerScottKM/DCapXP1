"use client";
import { useEffect, useState } from "react";

export default function AccountPage() {
  const [me, setMe] = useState<any>(null);
  const [form, setForm] = useState({
    legalName: "",
    country: "",
    dob: "",
    docType: "PASS",
    docHash: "",
  });
  const [submitting, setSubmitting] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function load() {
    const r = await fetch("/api/me", { cache: "no-store" });
    const j = await r.json();
    setMe(j.user ?? null);
  }
  useEffect(() => {
    load();
  }, []);

  async function submitKyc() {
    setSubmitting(true);
    setMsg(null);
    const r = await fetch("/api/kyc/submit", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(form),
    });
    setSubmitting(false);
    if (!r.ok) {
      setMsg("KYC submit failed");
      return;
    }
    setMsg("KYC submitted. Status: PENDING");
    load();
  }

  const card =
    "rounded-2xl border border-slate-200/70 bg-white/80 p-5 text-slate-900 shadow-sm backdrop-blur-md dark:border-slate-800/60 dark:bg-slate-950/40 dark:text-slate-100";
  const input =
    "w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-300 dark:border-slate-800/60 dark:bg-slate-950/30 dark:text-slate-100 dark:placeholder:text-slate-500 dark:focus:ring-indigo-700/40";

  return (
    <main className="min-h-screen bg-gradient-to-br from-white via-slate-50 to-indigo-50 text-slate-900 dark:from-slate-950 dark:via-slate-950 dark:to-indigo-950/20 dark:text-slate-100">
      <div className="mx-auto max-w-6xl px-6 py-8">
        <h1 className="mb-6 text-2xl font-semibold">Account & KYC</h1>

        <div className="grid gap-6 md:grid-cols-2">
          <div className={card}>
            <h2 className="mb-3 font-medium">Profile</h2>
            {!me && <div className="text-slate-600 dark:text-slate-400">Loading…</div>}
            {me && (
              <div className="space-y-1 text-sm">
                <div>
                  <span className="text-slate-600 dark:text-slate-400">Username:</span> {me.username}
                </div>
                <div>
                  <span className="text-slate-600 dark:text-slate-400">Created:</span>{" "}
                  {new Date(me.createdAt).toLocaleString()}
                </div>
              </div>
            )}

            <h3 className="mb-2 mt-6 font-medium">KYC</h3>
            {me?.kyc ? (
              <div className="space-y-1 text-sm">
                <div>
                  <span className="text-slate-600 dark:text-slate-400">Name:</span> {me.kyc.legalName}
                </div>
                <div>
                  <span className="text-slate-600 dark:text-slate-400">Country:</span> {me.kyc.country}
                </div>
                <div>
                  <span className="text-slate-600 dark:text-slate-400">Status:</span> {me.kyc.status}
                </div>
                <div>
                  <span className="text-slate-600 dark:text-slate-400">Risk Score:</span> {me.kyc.riskScore}
                </div>
              </div>
            ) : (
              <div className="text-sm text-slate-600 dark:text-slate-400">No KYC on file.</div>
            )}
          </div>

          <div className={card}>
            <h2 className="mb-3 font-medium">Submit / Update KYC</h2>

            <div className="space-y-3">
              <input
                className={input}
                placeholder="Legal Name"
                value={form.legalName}
                onChange={(e) => setForm({ ...form, legalName: e.target.value })}
              />
              <input
                className={input}
                placeholder="Country (e.g. AU)"
                value={form.country}
                onChange={(e) => setForm({ ...form, country: e.target.value })}
              />
              <input
                className={input}
                placeholder="DOB (YYYY-MM-DD)"
                value={form.dob}
                onChange={(e) => setForm({ ...form, dob: e.target.value })}
              />
              <select
                className={input}
                value={form.docType}
                onChange={(e) => setForm({ ...form, docType: e.target.value })}
              >
                <option value="PASS">Passport</option>
                <option value="DL">Driver License</option>
                <option value="NID">National ID</option>
              </select>
              <input
                className={input}
                placeholder="Document Hash (demo)"
                value={form.docHash}
                onChange={(e) => setForm({ ...form, docHash: e.target.value })}
              />

              <button
                onClick={submitKyc}
                disabled={submitting}
                className="rounded-xl border border-emerald-300 bg-emerald-50 px-4 py-2 font-medium text-emerald-900 hover:bg-emerald-100 disabled:opacity-50 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200 dark:hover:bg-emerald-500/15"
              >
                {submitting ? "Submitting…" : "Submit KYC"}
              </button>

              {msg ? (
                <div className="text-sm text-emerald-700 dark:text-emerald-300">{msg}</div>
              ) : null}

              <p className="text-xs text-slate-600 dark:text-slate-400">
                Demo only. Replace with proper doc capture & verification provider (e.g., Sumsub, Onfido).
              </p>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}
