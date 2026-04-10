declare module "node-vault" {
  export interface VaultClient {
    token?: string;
    read(path: string): Promise<any>;
    write(path: string, data?: Record<string, unknown>): Promise<any>;
    tokenRevokeSelf?(): Promise<any>;
  }

  export interface VaultOptions {
    endpoint: string;
    apiVersion?: string;
    token?: string;
    [key: string]: unknown;
  }

  export default function nodeVault(options?: VaultOptions): VaultClient;
}
