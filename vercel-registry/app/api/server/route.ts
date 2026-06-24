export const dynamic = 'force-dynamic';

// Returns the current backend URL. Set the `BACKEND_URL` env var on this
// Vercel project to the deployed resolver's URL; redeploy to update.
export async function GET() {
  const raw = process.env.BACKEND_URL ?? '';
  const url = raw.replace(/[﻿​\s]/g, '') || null; // strip BOM/zero-width
  return Response.json({ url, ts: Date.now() });
}
