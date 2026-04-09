import PortalShell from "../../src/components/portal/PortalShell";
import KycPage from "../../src/features/kyc/KycPage";

export default function KycRoute() {
  return (
    <PortalShell>
      <KycPage />
    </PortalShell>
  );
}
