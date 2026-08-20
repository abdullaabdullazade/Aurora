# Aurora Resolver Registry (Vercel)

Always-on pointer so the mobile app finds the PC resolver's **current** URL
even when the LAN IP changes. Deploy is separate from the resolver server.

## Deploy
1. `cd vercel-registry`
2. Push this folder to a GitHub repo (or `vercel` CLI).
3. On Vercel: **New Project** → import it.
4. **Storage → Add → Upstash Redis** (Marketplace) — auto-sets
   `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN`.
5. Add env var **`REGISTER_SECRET`** = a strong password.
6. Deploy → note the URL, e.g. `https://aurora-registry.vercel.app`.

## Endpoints
- `GET /api/server` → `{ url, ts }` — the current backend URL (mobile reads this).
- `POST /api/register` (header `x-secret: <REGISTER_SECRET>`, body `{ "url": "http://LAN_IP:8000" }`) — the PC resolver calls this every minute.
- `/` → status page showing the current backend.

## Wire it up
- PC resolver (`server/`): set env `REGISTRY_URL` + `REGISTER_SECRET`, run as usual — it self-registers.
- Mobile (`lib/core/config/app_config.dart`): set `registryUrl` to your Vercel URL. The app fetches the backend URL at launch (falls back to the hardcoded LAN IP).
