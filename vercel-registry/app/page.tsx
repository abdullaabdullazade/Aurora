import { kv, KEY_URL, KEY_TS } from '../lib/redis';

export const dynamic = 'force-dynamic';

export default async function Page() {
  let url: string | null = null;
  let ts: number | null = null;
  try {
    const redis = kv();
    if (redis) {
      url = (await redis.get<string>(KEY_URL)) ?? null;
      ts = (await redis.get<number>(KEY_TS)) ?? null;
    }
  } catch {
    /* redis not configured yet */
  }
  const seen = ts ? new Date(ts).toUTCString() : '—';

  return (
    <main
      style={{
        minHeight: '100vh',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 12,
        background: 'radial-gradient(1200px 600px at 50% -10%, #0c2a1b, #0b0c10)',
        color: '#fff',
        fontFamily: 'system-ui, sans-serif',
      }}
    >
      <h1 style={{ fontSize: 30, margin: 0, color: '#18FFB0' }}>
        🌌 Aurora Resolver Registry
      </h1>
      <p style={{ color: '#B3B3B3', margin: 0 }}>Current backend:</p>
      <code
        style={{
          background: '#181818',
          padding: '10px 16px',
          borderRadius: 999,
          border: '1px solid #ffffff1a',
        }}
      >
        {url ?? 'not registered yet'}
      </code>
      <p style={{ color: '#6E6E6E', fontSize: 13 }}>last seen: {seen}</p>
    </main>
  );
}
