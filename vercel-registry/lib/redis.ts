import { Redis } from '@upstash/redis';

export const KEY_URL = 'server_url';
export const KEY_TS = 'server_ts';

// Lazy + safe: returns null when Upstash env isn't configured yet, so the app
// still builds/deploys before storage is added.
export function kv(): Redis | null {
  // fromEnv() with missing vars builds a broken client that throws on use, so
  // check the env explicitly first.
  const url =
      process.env.UPSTASH_REDIS_REST_URL ?? process.env.KV_REST_API_URL;
  const token =
      process.env.UPSTASH_REDIS_REST_TOKEN ?? process.env.KV_REST_API_TOKEN;
  if (!url || !token) return null;
  try {
    return new Redis({ url, token });
  } catch {
    return null;
  }
}
