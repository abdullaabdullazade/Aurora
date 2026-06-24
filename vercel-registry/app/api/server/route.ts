import { redis, KEY_URL, KEY_TS } from '../../../lib/redis';

export const dynamic = 'force-dynamic';

// Mobile app calls this once to learn the PC resolver's current URL.
export async function GET() {
  const url = (await redis.get<string>(KEY_URL)) ?? null;
  const ts = (await redis.get<number>(KEY_TS)) ?? null;
  return Response.json({ url, ts });
}
