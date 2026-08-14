// Note added by me. Everything below it is the original starter code.
//
// This is a comment to show the differential CI and that the deploy works.
// Only orders depends on this package, so this change should rebuild and
// deploy orders alone, and leave inventory and notifications on the digests
// pinned in infra/envs/staging/terraform.tfvars.

export class HttpError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export interface JsonRequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  headers?: Record<string, string>;
  body?: unknown;
}

export async function fetchJson<T>(url: string, options: JsonRequestOptions = {}): Promise<T> {
  const response = await fetch(url, {
    method: options.method ?? (options.body ? "POST" : "GET"),
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      ...options.headers,
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new HttpError(`Request failed: ${response.status}`, response.status, text);
  }

  if (!text) {
    return undefined as T;
  }

  return JSON.parse(text) as T;
}
