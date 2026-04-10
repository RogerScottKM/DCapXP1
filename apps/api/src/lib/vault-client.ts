import nodeVault from "node-vault";

export type VaultSecretMap = Record<string, string>;

export interface VaultBootstrapConfig {
  enabled: boolean;
  addr: string;
  mountPath: string;
  roleId: string;
  secretId: string;
  secretPath: string;
}

function truthy(value: string | undefined): boolean {
  if (!value) return false;
  return ["1", "true", "yes", "on"].includes(value.trim().toLowerCase());
}

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function readSecretId(): string {
  const filePath = process.env.VAULT_SECRET_ID_FILE?.trim();
  if (filePath) {
    const fs = require("node:fs") as typeof import("node:fs");
    const value = fs.readFileSync(filePath, "utf8").trim();
    if (!value) {
      throw new Error(`VAULT_SECRET_ID_FILE is empty: ${filePath}`);
    }
    return value;
  }
  return requireEnv("VAULT_SECRET_ID");
}

function normalizeSecretValue(value: unknown): string {
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}

function extractSecretMap(payload: any): VaultSecretMap {
  const kvV2 = payload?.data?.data;
  const kvV1 = payload?.data;
  const source = kvV2 && typeof kvV2 === "object" ? kvV2 : kvV1 && typeof kvV1 === "object" ? kvV1 : null;
  if (!source || typeof source !== "object") {
    return {};
  }

  const result: VaultSecretMap = {};
  for (const [key, value] of Object.entries(source)) {
    if (value === undefined || value === null) continue;
    result[key] = normalizeSecretValue(value);
  }
  return result;
}

export function isVaultEnabled(): boolean {
  return truthy(process.env.VAULT_ENABLED);
}

export function getVaultBootstrapConfig(): VaultBootstrapConfig | null {
  if (!isVaultEnabled()) {
    return null;
  }

  return {
    enabled: true,
    addr: requireEnv("VAULT_ADDR"),
    mountPath: process.env.VAULT_MOUNT_PATH?.trim() || "approle",
    roleId: requireEnv("VAULT_ROLE_ID"),
    secretId: readSecretId(),
    secretPath: process.env.VAULT_SECRET_PATH?.trim() || "secret/data/dcapx/api",
  };
}

export async function fetchSecretsFromVault(): Promise<VaultSecretMap> {
  const config = getVaultBootstrapConfig();
  if (!config) {
    return {};
  }

  const client = nodeVault({
    endpoint: config.addr,
    apiVersion: "v1",
  });

  const login = await client.write(`auth/${config.mountPath}/login`, {
    role_id: config.roleId,
    secret_id: config.secretId,
  });

  const token = login?.auth?.client_token;
  if (!token || typeof token !== "string") {
    throw new Error("Vault AppRole login did not return a client token");
  }

  client.token = token;

  try {
    const secret = await client.read(config.secretPath);
    const values = extractSecretMap(secret);
    if (Object.keys(values).length === 0) {
      throw new Error(`Vault secret path returned no key/value pairs: ${config.secretPath}`);
    }
    return values;
  } finally {
    try {
      if (typeof client.tokenRevokeSelf === "function") {
        await client.tokenRevokeSelf();
      }
    } catch {
      // Best-effort revoke; let the short-lived token expire if revoke fails.
    }
  }
}
