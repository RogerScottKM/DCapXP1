"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.bootstrapSecrets = bootstrapSecrets;
const vault_client_1 = require("./vault-client");
function truthy(value) {
    if (!value)
        return false;
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
async function bootstrapSecrets() {
    if (!(0, vault_client_1.isVaultEnabled)()) {
        console.log("[vault] bootstrap disabled");
        return;
    }
    const secrets = await (0, vault_client_1.fetchSecretsFromVault)();
    const overrideExisting = truthy(process.env.VAULT_OVERRIDE_ENV);
    let applied = 0;
    for (const [key, value] of Object.entries(secrets)) {
        if (RESERVED_KEYS.has(key))
            continue;
        const current = process.env[key];
        if (overrideExisting || current === undefined || current === "") {
            process.env[key] = value;
            applied += 1;
        }
    }
    const path = process.env.VAULT_SECRET_PATH ?? "secret/data/dcapx/api";
    console.log(`[vault] loaded ${applied} secret values from ${path}`);
}
