"use client";

import { useState } from "react";
import type { Widget } from "@repo/schema/ui";

type Props = Extract<Widget, { type: "QuickOrder" }>;

export default function QuickOrderWidget({ symbol }: Props) {
  const [side, setSide] = useState<"BUY" | "SELL">("BUY");
  const [price, setPrice] = useState("100");
  const [qty, setQty] = useState("1");
  const [msg, setMsg] = useState<string>("");
  const [busy, setBusy] = useState(false);

  async function submit() {
    setMsg("");
    setBusy(true);

    try {
      const payload = { symbol, side, price, qty };

      const r = await fetch("/api/order", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const json = await r.json().catch(() => ({}));
      setMsg(json?.ok ? "Order placed ✅" : `Error: ${json?.error ?? "unknown"}`);
    } catch (e: any) {
      setMsg(`Error: ${String(e?.message ?? e)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="border rounded p-4">
      <div className="font-semibold">QuickOrder · {symbol}</div>

      <div className="mt-3 grid grid-cols-2 gap-2 text-sm">
        <select
          className="border rounded p-2"
          value={side}
          onChange={(e) => setSide(e.target.value as any)}
          disabled={busy}
        >
          <option value="BUY">BUY</option>
          <option value="SELL">SELL</option>
        </select>

        <input
          className="border rounded p-2"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
          placeholder="price"
          disabled={busy}
        />
        <input
          className="border rounded p-2"
          value={qty}
          onChange={(e) => setQty(e.target.value)}
          placeholder="qty"
          disabled={busy}
        />

        <button className="border rounded p-2" onClick={submit} disabled={busy}>
          {busy ? "Submitting..." : "Submit"}
        </button>
      </div>

      {msg ? <div className="text-sm mt-2 opacity-80">{msg}</div> : null}
    </div>
  );
}
