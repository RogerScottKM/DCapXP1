import fs from "node:fs";
import path from "node:path";

import * as dotenv from "dotenv";

const HOST_BOOTSTRAP_FILENAME = ".env.vault.host";

function fileExists(filePath: string): boolean {
  try {
    return fs.existsSync(filePath);
  } catch {
    return false;
  }
}

export function findRepoRoot(startDir: string): string | null {
  let current = path.resolve(startDir);

  while (true) {
    const markers = [
      path.join(current, "pnpm-workspace.yaml"),
      path.join(current, "docker-compose.yml"),
      path.join(current, ".git"),
    ];

    if (markers.some(fileExists)) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      return null;
    }
    current = parent;
  }
}

export function resolveVaultBootstrapFile(
  cwd: string = process.cwd(),
  scriptDir: string = __dirname,
  explicitPath?: string | null,
): string | null {
  const envOverride = explicitPath ?? process.env.VAULT_BOOTSTRAP_FILE ?? null;
  if (envOverride) {
    const resolved = path.resolve(envOverride);
    return fileExists(resolved) ? resolved : null;
  }

  const candidates = new Set<string>();

  candidates.add(path.resolve(cwd, HOST_BOOTSTRAP_FILENAME));

  const cwdRoot = findRepoRoot(cwd);
  if (cwdRoot) {
    candidates.add(path.join(cwdRoot, HOST_BOOTSTRAP_FILENAME));
  }

  const scriptRoot = findRepoRoot(scriptDir);
  if (scriptRoot) {
    candidates.add(path.join(scriptRoot, HOST_BOOTSTRAP_FILENAME));
  }

  for (const candidate of candidates) {
    if (fileExists(candidate)) {
      return candidate;
    }
  }

  return null;
}

export function loadVaultBootstrapEnv(
  cwd: string = process.cwd(),
  scriptDir: string = __dirname,
): string | null {
  const resolved = resolveVaultBootstrapFile(cwd, scriptDir);
  if (!resolved) {
    return null;
  }

  dotenv.config({
    path: resolved,
    override: true,
  });

  return resolved;
}
