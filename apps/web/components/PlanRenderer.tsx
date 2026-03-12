// apps/web/components/PlanRenderer.tsx
import type { LayoutItem } from "@repo/schema/ui";
import WidgetRenderer from "./WidgetRenderer";

export default function PlanRenderer({ layout }: { layout: LayoutItem[] }) {
  const sorted = [...layout].sort((a, b) => a.priority - b.priority);

  return (
    <div className="grid grid-cols-3 gap-4">
      {sorted.map((item) => (
        <div key={item.id} className={colSpanClass(item.colSpan)}>
          <WidgetRenderer widget={item.widget} />
        </div>
      ))}
    </div>
  );
}

function colSpanClass(colSpan: number) {
  if (colSpan === 1) return "col-span-3 md:col-span-1";
  if (colSpan === 2) return "col-span-3 md:col-span-2";
  return "col-span-3";
}
