"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.maskDatabaseUrl = maskDatabaseUrl;
exports.collectVaultContext = collectVaultContext;
const dotenv = __importStar(require("dotenv"));
const bootstrap_secrets_1 = require("../lib/bootstrap-secrets");
const vault_bootstrap_env_1 = require("./vault-bootstrap-env");
dotenv.config();
function maskDatabaseUrl(url) {
    if (!url)
        return null;
    return url.replace(/:([^:@/]+)@/, ":****@");
}
async function collectVaultContext(env = process.env) {
    const bootstrapFile = (0, vault_bootstrap_env_1.loadVaultBootstrapEnv)(process.cwd(), __dirname);
    await (0, bootstrap_secrets_1.bootstrapSecrets)();
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
async function main() {
    try {
        const context = await collectVaultContext();
        console.log(JSON.stringify(context, null, 2));
    }
    catch (error) {
        console.error("[vault-context] failed", error);
        process.exit(1);
    }
}
if (require.main === module) {
    void main();
}
