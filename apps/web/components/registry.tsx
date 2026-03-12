// apps/web/components/registry.tsx
import 'server-only';

import type { WidgetProps } from '@repo/schema/ui';

import SimpleChartWidget from '@/components/widgets/SimpleChartWidget';
import RiskWarningWidget from '@/components/widgets/RiskWarningWidget';
import PlaceholderWidget from '@/components/widgets/PlaceholderWidget';
import ErrorStateWidget from "@/components/widgets/ErrorStateWidget";

export function AgentWidgetRenderer(widget: WidgetProps) {
  switch (widget.type) {
    case 'RiskWarning':
      return <RiskWarningWidget {...widget} />;

    case 'SimpleChart':
      return <SimpleChartWidget {...widget} />;

    // For now: placeholders (we’ll replace with real widgets next)
    case 'OrderBook':
      return <PlaceholderWidget title="OrderBook" data={widget} />;

    case 'QuickOrder':
      return <PlaceholderWidget title="QuickOrder" data={widget} />;

    case 'TradeHistory':
      return <PlaceholderWidget title="TradeHistory" data={widget} />;

    case 'ProChart':
      return <PlaceholderWidget title="ProChart" data={widget} />;

    case 'Onboarding':
      return <PlaceholderWidget title="Onboarding" data={widget} />;

    case 'PortfolioSummary':
      return <PlaceholderWidget title="PortfolioSummary" data={widget} />;

    case "ErrorState":
      return (
        <ErrorStateWidget
         title={widget.title}
         message={widget.message}
         recoverable={widget.recoverable} />
      );

    default: {
      const _exhaustive: never = widget;
      return <PlaceholderWidget title="UnknownWidget" data={widget as any} />;
    }
  }
}
