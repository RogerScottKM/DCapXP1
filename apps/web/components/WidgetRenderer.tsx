// apps/web/components/WidgetRenderer.tsx
import type { Widget } from "@repo/schema/ui";

import RiskWarningWidget from "./widgets/RiskWarningWidget";
import SimpleChartWidget from "./widgets/SimpleChartWidget";
import OrderBookWidget from "./widgets/OrderBookWidget";
import TradeHistoryWidget from "./widgets/TradeHistoryWidget";
import QuickOrderWidget from "./widgets/QuickOrderWidget";

export default function WidgetRenderer({ widget }: { widget: Widget }) {
  switch (widget.type) {
    case "RiskWarning":
      return <RiskWarningWidget {...widget} />;
    case "SimpleChart":
      return <SimpleChartWidget {...widget} />;
    case "OrderBook":
      return <OrderBookWidget {...widget} />;
    case "TradeHistory":
      return <TradeHistoryWidget {...widget} />;
    case "QuickOrder":
      return <QuickOrderWidget {...widget} />;
    default:
      return (
        <pre className="text-xs p-4 border rounded">
          {JSON.stringify(widget, null, 2)}
        </pre>
      );
  }
}
