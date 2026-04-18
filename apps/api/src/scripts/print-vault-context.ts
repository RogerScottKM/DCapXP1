import * as dotenv from "dotenv";

import { bootstrapSecrets } from "../lib/bootstrap-secrets";
import { loadVaultBootstrapEnv, resolveVaultBootstrapFile } from "./vault-bootstrap-env";

dotenv.config();

export function maskDatabaseUrl(url?: string | null): string | null {
  if (!url) return null;
  return url.replace(/:([^:@/]+)@/, ":****@");
}

export async function collectVaultContext(
  env: NodeJS.ProcessEnv = process.env,
): Promise<Record<string, unknown>> {
  const bootstrapFile = loadVaultBootstrapEnv(process.cwd(), __dirname);
  await bootstrapSecrets();

  return {
    bootstrapFile,
    VAULT_ENABLED: env.VAULT_ENABLED ?? null,
    hasVaultAddr: Boolean(env.VAULT_ADDR),
    hasVaultRoleId: Boolean(env.VAULT_ROLE_ID),
    hasVaultSecretId: Boolean(env.VAULT_SECRET_ID),
    hasVaultSecretIdFile: Boolean(env.VAULT_SECRET_ID_FILE),
    VAULT_SECRET_PATH: env.VAULT_SECRET_PATH ?? null,
    VAULT_OVERRIDE_ENV: env.VAULT_OVERRIDE_ENV ?? null,
    hasDatabaseUrl: Boolean(env.DATABASE_URL),
    databaseUrlMasked: maskDatabaseUrl(env.DATABASE_URL),
  };
}

async function main(): Promise<void> {
  try {
    const context = await collectVaultContext();
    console.log(JSON.stringify(context, null, 2));
  } catch (error) {
    console.error("[vault-context] failed", error);
    process.exit(1);
  }
}

if (require.main === module) {
  void main();
}
