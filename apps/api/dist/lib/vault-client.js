"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.isVaultEnabled = isVaultEnabled;
exports.getVaultBootstrapConfig = getVaultBootstrapConfig;
exports.fetchSecretsFromVault = fetchSecretsFromVault;
const node_vault_1 = __importDefault(require("node-vault"));
function truthy(value) {
    if (!value)
        return false;
    return ["1", "true", "yes", "on"].includes(value.trim().toLowerCase());
}
function requireEnv(name) {
    const value = process.env[name]?.trim();
    if (!value) {
        throw new Error(`${name} is required`);
    }
    return value;
}
function readSecretId() {
    const filePath = process.env.VAULT_SECRET_ID_FILE?.trim();
    if (filePath) {
        const fs = require("node:fs");
        const value = fs.readFileSync(filePath, "utf8").trim();
        if (!value) {
            throw new Error(`VAULT_SECRET_ID_FILE is empty: ${filePath}`);
        }
        return value;
    }
    return requireEnv("VAULT_SECRET_ID");
}
function normalizeSecretValue(value) {
    if (typeof value === "string")
        return value;
    return JSON.stringify(value);
}
function extractSecretMap(payload) {
    const kvV2 = payload?.data?.data;
    const kvV1 = payload?.data;
    const source = kvV2 && typeof kvV2 === "object" ? kvV2 : kvV1 && typeof kvV1 === "object" ? kvV1 : null;
    if (!source || typeof source !== "object") {
        return {};
    }
    const result = {};
    for (const [key, value] of Object.entries(source)) {
        if (value === undefined || value === null)
            continue;
        result[key] = normalizeSecretValue(value);
    }
    return result;
}
function isVaultEnabled() {
    return truthy(process.env.VAULT_ENABLED);
}
function getVaultBootstrapConfig() {
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
async function fetchSecretsFromVault() {
    const config = getVaultBootstrapConfig();
    if (!config) {
        return {};
    }
    const client = (0, node_vault_1.default)({
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
    }
    finally {
        try {
            if (typeof client.tokenRevokeSelf === "function") {
                await client.tokenRevokeSelf();
            }
        }
        catch {
            // Best-effort revoke; let the short-lived token expire if revoke fails.
        }
    }
}
