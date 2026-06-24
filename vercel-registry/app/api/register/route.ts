import { redis, KEY_URL, KEY_TS } from '../../../lib/redis';

export const dynamic = 'force-dynamic';

// The PC resolver POSTs its current LAN URL here every minute.
// Protected by a shared secret (REGISTER_SECRET env var).
export async function POST(req: Request) {
  if (req.headers.get('x-secret') !== process.env.REGISTER_SECRET) {
    return new Response('Unauthorized', { status: 401 });
  }
  let body: { url?: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }
  if (!body.url) return new Response('Missing url', { status: 400 });

  await redis.set(KEY_URL, body.url);
  await redis.set(KEY_TS, Date.now());
  return Response.json({ ok: true, url: body.url });
}
