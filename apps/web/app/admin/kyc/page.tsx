'use client';

import { useEffect, useState } from 'react';

type Kyc = {
  id: number;
  userId: number;
  legalName: string;
  country: string;
  dob: string;
  docType: string;
  docHash: string;
  status: 'PENDING'|'APPROVED'|'REJECTED';
  riskScore: string;
  createdAt: string;
};

export default function AdminKyc() {
  const [rows, setRows] = useState<Kyc[]>([]);
  const [msg, setMsg] = useState<string|null>(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    const r = await fetch('/api/admin/kyc/pending', { cache:'no-store' });
    const j = await r.json();
    setRows(j.items ?? []);
  }

  async function setStatus(id:number, status:'APPROVED'|'REJECTED') {
    setBusy(true); setMsg(null);
    const r = await fetch(`/api/admin/kyc/${id}/status`, {
      method:'PATCH',
      headers:{ 'content-type':'application/json' },
      body: JSON.stringify({ status }),
    });
    const j = await r.json();
    setBusy(false);
    setMsg(j.ok ? `Updated #${id} -> ${status}` : `Failed: ${j.error ?? 'unknown'}`);
    await load();
  }

  useEffect(()=>{ load(); }, []);

  return (
    <div className="max-w-6xl mx-auto px-6 py-8">
      <h1 className="text-3xl font-bold mb-6">Admin · KYC Queue</h1>
      {msg && <div className="mb-4 rounded-xl border border-slate-700 bg-slate-900/40 px-4 py-3 text-sm">{msg}</div>}

      <div className="rounded-2xl border border-slate-800/60 bg-slate-900/30 overflow-hidden">
        <table className="w-full">
          <thead className="bg-slate-900/60">
            <tr className="text-left text-slate-300">
              <th className="px-4 py-2">ID</th>
              <th className="px-4 py-2">User</th>
              <th className="px-4 py-2">Name</th>
              <th className="px-4 py-2">Country</th>
              <th className="px-4 py-2">Doc</th>
              <th className="px-4 py-2">Risk</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody>
            {rows.length===0 && <tr><td className="px-4 py-4 text-slate-400" colSpan={8}>No pending KYCs.</td></tr>}
            {rows.map(k=>(
              <tr key={k.id} className="border-t border-slate-800">
                <td className="px-4 py-2">{k.id}</td>
                <td className="px-4 py-2">{k.userId}</td>
                <td className="px-4 py-2">{k.legalName}</td>
                <td className="px-4 py-2">{k.country}</td>
                <td className="px-4 py-2">{k.docType}</td>
                <td className="px-4 py-2">{k.riskScore}</td>
                <td className="px-4 py-2">{k.status}</td>
                <td className="px-4 py-2 flex gap-2">
                  <button disabled={busy} onClick={()=>setStatus(k.id,'APPROVED')}
                          className="rounded-xl bg-emerald-600/90 px-3 py-1 text-sm hover:bg-emerald-600 disabled:opacity-60">Approve</button>
                  <button disabled={busy} onClick={()=>setStatus(k.id,'REJECTED')}
                          className="rounded-xl bg-rose-600/90 px-3 py-1 text-sm hover:bg-rose-600 disabled:opacity-60">Reject</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
