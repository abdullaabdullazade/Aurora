import { Redis } from '@upstash/redis';

// Uses UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN env vars, which the
// Vercel Marketplace Upstash Redis integration sets automatically.
export const redis = Redis.fromEnv();

export const KEY_URL = 'server_url';
export const KEY_TS = 'server_ts';
