import React from "react";

export default function ErrorStateWidget(props: {
  title: string;
  message: string;
  recoverable?: boolean;
}) {
  const { title, message, recoverable } = props;

  return (
    <div className="rounded-xl border p-4">
      <div className="text-lg font-semibold">{title}</div>
      <div className="mt-2 text-sm opacity-80">{message}</div>

      {recoverable ? (
        <div className="mt-3 text-xs opacity-60">
          Recoverable: yes (try refresh / re-run)
        </div>
      ) : (
        <div className="mt-3 text-xs opacity-60">Recoverable: no</div>
      )}
    </div>
  );
}
