# Aurora Resolver Server

FastAPI + yt-dlp backend for the [Aurora Music](https://github.com/abdullaabdullazade/Aurora) Android app. Handles YouTube search, playlist import, audio streaming (HTTP Range), Firebase sync, and optional lyrics.

## Quick start (Docker Compose)

Recommended for Synology NAS, VPS, and any Docker host. Compose builds the image from this folder's `Dockerfile`.

1. Prepare the folder:

```bash
cd /path/to/repo/server
cp .env.example .env
mkdir -p cache data
```

2. Edit `.env` — minimum required:

```bash
AURORA_SECRET_KEY=your_shared_secret
FIREBASE_PROJECT_ID=your-firebase-project-id
```

3. Start:

```bash
docker compose up -d --build
```

4. Verify:

```bash
curl http://localhost:8000/health
# {"ok":true}
```

## docker-compose.yml

```yaml
services:
  aurora:
    build: .
    network_mode: "host"         # registry gets the real LAN IP:8000
    env_file:
      - .env
    volumes:
      - ./cache:/app/cache       # stream cache
      - ./data:/app/data         # user sync DB
```

Uvicorn listens on **8000** with **2 workers**. Downloads use a **cross-process file lock** per video id so workers do not race yt-dlp on the same cold miss. Host networking is used so the URL published to the LAN registry (`REGISTRY_URL`) is reachable by the app; if you switch to a `ports:` mapping, keep host and container port identical (e.g. `"8000:8000"`) or registry auto-discovery advertises the wrong port.

## Synology NAS

1. Copy the `server/` folder into a shared folder, e.g. `docker/aurora`, and add your `.env`.
2. Create subfolders `cache` and `data` (or let Docker create them on first run).
3. In **Container Manager** → Project → create from `docker-compose.yml`, or via SSH:

```bash
cd /volume1/docker/aurora
docker compose up -d --build
```

4. Reverse proxy (Cloudflare, Synology reverse proxy) → `http://NAS_IP:8000`.

**Upgrade:** pull the new server code, then `docker compose up -d --build`. Your `.env`, `cache/`, and `data/` are preserved.

## docker run (without Compose)

```bash
docker build -t aurora-server .

docker run -d --name aurora-server \
  --network host \
  --env-file .env \
  -v ./cache:/app/cache \
  -v ./data:/app/data \
  --restart unless-stopped \
  aurora-server
```

## Required environment variables

| Variable | Description |
|----------|-------------|
| `AURORA_SECRET_KEY` | Shared secret with the Android app (`x-api-key` header). Required for public deployment. |
| `FIREBASE_PROJECT_ID` | Firebase project ID for authenticated sync (`/sync`). |

## Optional environment variables

| Variable | Description |
|----------|-------------|
| `AURORA_CACHE_MAX_BYTES` | Stream cache limit (`unlimited`, `10GB`, `500MB`, …). |
| `YT_COOKIES_B64` | Base64-encoded YouTube cookies to reduce bot blocks on VPS/datacenter IPs. |
| `YOUTUBE_API_KEY` | YouTube Data API v3 key (optional; not needed for core search/stream). |
| `REGISTRY_URL` / `REGISTER_SECRET` | Vercel LAN registry auto-registration. |
| `PORT` | Port advertised to the LAN registry only — **not** uvicorn (container always uses 8000). |

Copy the full template from [`.env.example`](.env.example).

## Volumes

| Host path | Container path | Purpose |
|-----------|----------------|---------|
| `./cache` | `/app/cache` | Stream cache (SQLite + audio files) |
| `./data` | `/app/data` | Per-user sync database (SQLite) |

Do not delete these folders unless you intend to wipe cached streams or synced account data.

## CI: publish a new image

GitHub Actions workflow [`.github/workflows/docker-hub.yml`](../.github/workflows/docker-hub.yml) builds and pushes `<DOCKERHUB_USERNAME>/aurora-server` on every push to `main` that changes `server/**`. It is skipped until both are configured:

| Name | Kind | Value |
|------|------|--------|
| `DOCKERHUB_USERNAME` | Actions variable | Docker Hub account that owns the image |
| `DOCKERHUB_TOKEN` | Actions secret | Docker Hub access token (Read & Write) |

Manual trigger: GitHub → **Actions** → **Publish Docker Hub** → **Run workflow**.

## Run without Docker (developers)

```bash
python -m pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --env-file .env
```

## API endpoints

- `GET /health` — no auth
- `GET /search?q=...&limit=20`
- `GET /playlist?url=...`
- `GET /stream?v=VIDEO_ID` — audio with Range support
- `GET /sync` / `PUT /sync` — Firebase-authenticated user data

All endpoints except `/health` require `x-api-key: <AURORA_SECRET_KEY>` when the secret is configured.
