export const dynamic = 'force-dynamic';

// Returns the current backend URL. Set the `BACKEND_URL` env var on this
// Vercel project to the deployed resolver's URL; redeploy to update.
export async function GET() {
  return Response.json({
    url: process.env.BACKEND_URL ?? null,
    ts: Date.now(),
  });
}
