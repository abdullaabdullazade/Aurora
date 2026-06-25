export const dynamic = 'force-dynamic';

const clean = (s: string) => s.replace(/[﻿​\s]/g, ''); // strip BOM/zero-width/space

// Source of truth is the `backend_url` key in Edge Config (the VPS PATCHes it
// on every cloudflared restart — no redeploy). We read it via the connection
// string with `no-store` so a warm function never serves a stale URL (the
// @vercel/edge-config SDK caches in-memory per instance, which we must avoid).
// Falls back to the BACKEND_URL env var if Edge Config is unset/unavailable.
async function fromEdgeConfig(): Promise<string> {
  const conn = process.env.EDGE_CONFIG;
  if (!conn) return '';
  try {
    const [base, query] = conn.split('?');
    const res = await fetch(`${base}/item/backend_url?${query}`, {
      cache: 'no-store',
    });
    if (!res.ok) return '';
    const v = await res.json();
    return typeof v === 'string' ? v : '';
  } catch {
    return '';
  }
}

export async function GET() {
  let raw = await fromEdgeConfig();
  if (!raw) raw = process.env.BACKEND_URL ?? '';
  const url = clean(raw) || null;
  return Response.json({ url, ts: Date.now() });
}
