import type { Widget } from "@repo/schema/ui";
type Props = Extract<Widget, { type: "RiskWarning" }>;

export default function RiskWarningWidget({ level, message }: Props) {
  return (
    <div className="border rounded p-4">
      <div className="font-semibold">Risk ({level})</div>
      <div className="text-sm opacity-80 mt-1">{message}</div>
    </div>
  );
}
