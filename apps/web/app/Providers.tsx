"use client";

import type { ReactNode } from "react";
import { PortalPreferencesProvider } from "../src/lib/preferences/PortalPreferencesProvider";

export default function Providers({ children }: { children: ReactNode }) {
  return <PortalPreferencesProvider>{children}</PortalPreferencesProvider>;
}
