// apps/web/components/widgets/PlaceholderWidget.tsx
export default function PlaceholderWidget({ title, data }: { title: string; data: unknown }) {
  return (
    <div className="rounded-xl border border-slate-700 bg-slate-900/20 p-4">
      <div className="text-xs font-mono text-slate-400">{title} (placeholder)</div>
      <pre className="mt-2 overflow-auto rounded-lg bg-black/30 p-3 text-[11px] text-slate-300">
        {JSON.stringify(data, null, 2)}
      </pre>
    </div>
  );
}
