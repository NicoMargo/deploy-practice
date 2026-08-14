import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import * as grpc from "@grpc/grpc-js"; //ADDED

export interface SecretsClient {
  accessSecret(secretId: string, version?: string): Promise<string>;
}

export class MissingSecretError extends Error {
  constructor(readonly secretId: string) {
    super(`Required secret is missing or empty: ${secretId}`);
    this.name = "MissingSecretError";
  }
}

//ADDED
function buildClient(): SecretManagerServiceClient {
    const emulatorHost = process.env.SECRET_MANAGER_EMULATOR_HOST;
    if (!emulatorHost) {
      return new SecretManagerServiceClient();
    }
    const [host, port] = emulatorHost.split(":");
    return new SecretManagerServiceClient({
      apiEndpoint: host,
      port: Number(port),
      sslCreds: grpc.credentials.createInsecure(),
    });
  }


/**
 * Thin Secret Manager accessor.
 *
 * Point at floci-gcp with SECRETMANAGER_EMULATOR_HOST (or floci gcp env).
 * How Cloud Run obtains identity / whether values are injected instead of
 * fetched at runtime is intentionally left for the homework solution.
 */
export function createSecretsClient(projectId = process.env.GCP_PROJECT_ID ?? "floci-local"): SecretsClient {
    
  //const client = new SecretManagerServiceClient(); //DELETED

    const client = buildClient(); //ADDED

    return {
    async accessSecret(secretId: string, version = "latest"): Promise<string> {
      const name = `projects/${projectId}/secrets/${secretId}/versions/${version}`;
      const [response] = await client.accessSecretVersion({ name });
      const value = response.payload?.data?.toString();
      if (!value) {
        throw new MissingSecretError(secretId);
      }
      return value;
    },
  };
}
  

/** Constant-time-ish compare for small API tokens (not for passwords). */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let mismatch = 0;
  for (let i = 0; i < a.length; i += 1) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
