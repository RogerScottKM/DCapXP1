import { fetchSecretsFromVault, isVaultEnabled } from "./vault-client";

function truthy(value: string | undefined): boolean {
  if (!value) return false;
  return ["1", "true", "yes", "on"].includes(value.trim().toLowerCase());
}

const RESERVED_KEYS = new Set([
  "VAULT_ENABLED",
  "VAULT_ADDR",
  "VAULT_ROLE_ID",
  "VAULT_SECRET_ID",
  "VAULT_SECRET_ID_FILE",
  "VAULT_SECRET_PATH",
  "VAULT_MOUNT_PATH",
  "VAULT_OVERRIDE_ENV",
]);

export async function bootstrapSecrets(): Promise<void> {
  if (!isVaultEnabled()) {
    console.log("[vault] bootstrap disabled");
    return;
  }

  const secrets = await fetchSecretsFromVault();
  const overrideExisting = truthy(process.env.VAULT_OVERRIDE_ENV);
  let applied = 0;

  for (const [key, value] of Object.entries(secrets)) {
    if (RESERVED_KEYS.has(key)) continue;
    const current = process.env[key];
    if (overrideExisting || current === undefined || current === "") {
      process.env[key] = value;
      applied += 1;
    }
  }

  const path = process.env.VAULT_SECRET_PATH ?? "secret/data/dcapx/api";
  console.log(`[vault] loaded ${applied} secret values from ${path}`);
}
