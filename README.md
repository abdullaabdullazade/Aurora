<div align="center">

<img src="docs/icons/logo.svg" width="88" alt="Aurora Music logo">

# Aurora Music

### Premium music player — YouTube-Music power, Spotify-grade soft-dark glass design.

real search & streaming · synced lyrics · offline downloads · on-device library · playlists

**[Download latest APK](https://github.com/abdullaabdullazade/Aurora/releases/latest/download/Aurora-Music.apk)** · **[Website](https://abdullaabdullazade.github.io/Aurora/)** · **[Video demo](docs/media/aurora-demo.mp4)**

</div>

---

> **Flutter** front-end + a **Python (FastAPI + yt-dlp) resolver server**. All YouTube
> extraction happens server-side and audio is range-proxied, so the app never hits the
> `403` / rate-limiting that pure client-side scraping does.

```
Flutter app  ──HTTP──▶  FastAPI + yt-dlp  ──▶  YouTube
             ◀──audio/mp4 (Range)──
```

---

## <img src="docs/icons/demo.svg" width="22" align="top"> Demo

**[▶ Watch the walkthrough (2:34, with sound)](docs/media/aurora-demo.mp4)**

| Home | Now Playing | Synced lyrics | Lyric card |
|---|---|---|---|
| ![Home](docs/media/01-home.png) | ![Now Playing](docs/media/04-player.png) | ![Lyrics](docs/media/05-lyrics.png) | ![Lyric card](docs/media/06-lyric-card.png) |
| **Autocomplete** | **Search results** | **Up Next** | **Track menu** |
| ![Autocomplete](docs/media/02-search-suggestions.png) | ![Results](docs/media/03-search-results.png) | ![Queue](docs/media/07-queue.png) | ![Track menu](docs/media/11-download.png) |
| **Liked** | **Sleep timer** | **Downloaded** | **Playlists** |
| ![Liked](docs/media/10-liked.png) | ![Sleep timer](docs/media/12-sleep.png) | ![Downloaded](docs/media/13-downloaded.png) | ![Playlists](docs/media/16-playlists.png) |
| **Imported playlist** | **Settings** | **Crossfade** | **Listening stats** |
| ![Import](docs/media/15-import.png) | ![Settings](docs/media/08-settings.png) | ![Crossfade](docs/media/14-crossfade.png) | ![Stats](docs/media/09-stats.png) |

---

## <img src="docs/icons/features.svg" width="22" align="top"> Features

### <img src="docs/icons/search.svg" width="18" align="top"> Discovery & search
- **Real YouTube search** through the resolver — debounced 350 ms, with **Tracks / Playlists / Albums / Podcasts** chips that actually change the query (`filter` on `/search`). Tracks play in the queue; playlists, albums, and podcasts open a browse screen that loads the list via `/playlist`, then **Play all**, **save the whole list to your Library in one tap** (+ next to Play all), pick a track, or **add any track to your playlists** (same sheet as on Track search results).
- **Live autocomplete** from YouTube's own suggestion endpoint, plus a persisted **search history** (tap to re-run, per-item delete, one-tap clear). Search lives on the bottom-nav **Search** tab (no search icon in the Home app bar).
- **Home dashboard**: parallax header with the **profile avatar on the left** (opens Settings) and **Aurora on the right**, a time-of-day greeting (**Good morning** / **Good afternoon** / **Good evening**), a **2×2 quick-access grid** of up to four playlists (recently played, filled from Library when history is empty — tap opens the playlist, does not auto-play), plus carousels for **For you** (personalized from listening history), Trending, Top Charts, Recently played and Quick downloads. Engagement tips that used to sit under a bell icon are now **Settings → Notifications**.
- **Three states, one height** per section — shimmer skeleton, empty card, error card with a **Retry pill** that refetches only that carousel. Nothing jumps when a future resolves.

### <img src="docs/icons/play.svg" width="18" align="top"> Playback
- Audio streams through the proxy as `audio/mp4` over HTTP **Range** — seeking is instant.
- **Dual source**: remote YouTube and local device files run through the same `just_audio` engine.
- Queue with **shuffle**, **repeat one/all** and **drag-to-reorder**. Continuous playthrough: when a track ends, the next one **loads and starts automatically** — including with the screen locked or the app in the background (the media foreground service stays up between tracks so Dart can finish resolve / warm / play). Order is sequential, or random when shuffle is on — failed loads stay on the current track (retry / Play), they never auto-skip ahead. **Pause stays paused**: user pause wins over autoplay retries and mid-load start. Returning to the app after a stuck advance finishes `next()` or `play()` if you had not paused. Before ExoPlayer starts a remote song the app **waits for the resolver cache** (`Range` probe). Stream probes are **serialized** and an in-flight warm is **cancelled or reused** on advance. End-of-track stuck detection only fires at the true end (not during crossfade). Remote songs use a **single `AudioSource.uri`**. The next remote track is **warmed** after the current one is playing.
- **Crossfade**, 2–12 s, adjustable.
- **Remember playback position** (Settings → Audio, on by default) — after closing the app, the **mini-player** reappears immediately with the last track, artwork, and progress bar. Audio loads only when you press Play and resumes from the saved scrub position. Session data stays on-device (not synced to the server).
- **Sleep timer**: 5–60 min presets or **End of track**, with a 10-second fade-out. Open it from the **⋯** menu on the Now Playing screen.
- 5-band **equalizer**, playback **speed**, **audio output** sheet on Now Playing (lists this phone, wired headphones, and bonded Bluetooth by name; tap connects/disconnects via system A2DP — the OS owns media routing; **More** opens Bluetooth settings to scan/pair), right-edge **volume drag HUD**.

### <img src="docs/icons/player.svg" width="18" align="top"> The Now-Playing screen
- Full-screen layout: blurred artwork behind a colour veil derived from the cover.
- **Swipe down to dismiss** — drag the screen down to return to the mini-player without pausing playback (same as collapsing the player).
- **Minimal top bar** — centred title with a plain **⋯** menu (no chevron or separate sleep-timer icon). Sleep timer lives in that menu, above track actions.
- **Scrolling track title** — long titles marquee in a continuous loop on one line with the **like** heart fixed on the right (short titles stay still).
- **Two-role dynamic colour** — a vivid *accent* for marks, a deep same-hue *backdrop* for the wash, each held to its WCAG ratio. See [Colour](#colour).
- **Waveform seeker** — custom-painted bars with an elastic bump near the finger and a haptic tick per bar. In-app progress (mini-player and Now Playing) is polled while audio plays so the bar stays in sync even when `just_audio`'s position stream stalls; the Android media notification continues to interpolate independently.
- **Album-art pulse**: orbiting particles and a breathing ring that speeds up while playing.
- **Synced lyrics** (lrclib) that open at and follow the active line; tap a line to seek. While the lyrics sheet is open the **screen stays on** (wake lock); closing the sheet releases it.
- **Shareable lyric card** — hold a line, pick 1–6 lines, share as a rendered PNG.

### <img src="docs/icons/library.svg" width="18" align="top"> Library
- Tabs: **Playlists · On device · Downloaded · Queue**.
- **Import from a link** — paste a YouTube playlist / album / mix URL, get a local playlist.
- **Liked Songs** with an optional **auto-download** switch that also backfills earlier likes.
- **Downloads**: MP3 + lyrics, pause / resume / cancel, offline playback, set as **ringtone** or **alarm**. Optional **Download over Wi‑Fi only** (Settings → Library, off by default) — blocks new/resume transfers on mobile data and pauses active ones when Wi‑Fi drops.
- **On-device music** via MediaStore, grouped by folder, with per-folder show/hide.
- **Listening stats**: hours listened, play counts, top artists, most played.

### <img src="docs/icons/offline.svg" width="18" align="top"> Offline Sanctuary
- Connectivity is watched live. Offline, non-downloaded items **fade to 40 %** and stop responding, and a breathing **"Offline Sanctuary"** pill appears under the header.

### <img src="docs/icons/spark.svg" width="18" align="top"> Micro-interactions
- **Aurora pull-to-refresh** — a glowing orb that scales with overscroll, not the Material spinner.
- ~300 ms cross-fades, fade-up page transitions, `HapticFeedback` on play/pause, nav, scrub and toggles.
- Real `BackdropFilter` glass everywhere, each surface in its own `RepaintBoundary`.

---

## <img src="docs/icons/design.svg" width="22" align="top"> Design system — "Soft Dark / Glass"

### <img src="docs/icons/contrast.svg" width="18" align="top"> Colour

Artwork colours have to fill two jobs that pull in opposite directions, and using one colour
for both is what makes dynamic-theme players unreadable. `core/theme/dynamic_palette.dart`
splits them and holds each to a WCAG 2.1 ratio:

| Role | Derivation | Guarantee |
|---|---|---|
| `Tone.accent` | vivid, lightened until it passes | **≥ 3:1** vs the darkest surface (non-text UI minimum) |
| `Tone.backdrop` | same hue, desaturated, darkened until it passes | **≥ 4.5:1** for the dimmest label drawn on it |
| `Tone.onColor` | black or white, whichever scores higher | a legible glyph on any accent |

The veil stays neutral until `palette_generator` returns, then cross-fades in — before that a
track only carries an id-hash colour, which has nothing to do with its cover.

Glass surfaces also put a dark scrim under their white sheen: `BackdropFilter` preserves the
colour behind it, so a white-only fill turns into a bright smear over album art.

### <img src="docs/icons/tokens.svg" width="18" align="top"> Tokens

| Token | Value | Use |
|---|---|---|
| Void black | `#0B0C10` | deepest background |
| Base / Elevated | `#121212` · `#181818` · `#242424` | surfaces, cards |
| Emerald / Neon | `#1DB954` · `#00E676` | accent, playback, glow |
| Text | `#FFFFFF` · `#B3B3B3` · `#9A9A9A` | primary · muted · tertiary |
| Glass stroke | `white @ 10 %` | hairline borders |

**Type** Plus Jakarta Sans on a tight scale (`AppType`) · **Spacing/radii** 4-pt scale (`Sp`, `Radii`) ·
**Motion** fade-through with a slight upward slide on route push.

---

## <img src="docs/icons/architecture.svg" width="22" align="top"> Architecture — Clean Architecture + Riverpod

```
lib/
├── core/          config · theme (incl. dynamic_palette) · db (Hive) · audio · notifications
├── domain/        entities (Track, Playlist, LyricLine) · repository contracts
├── data/          ApiMusicRepository (Dio → resolver) · Mock repository
└── presentation/
    ├── state/     Riverpod controllers: player · downloads · playlists · favorites · settings
    ├── widgets/   Glass · AmbientBackground · Artwork · WaveformSeeker · AlbumPulse · …
    └── screens/   home · search · library · player · settings
```

**Rules** — no business logic in views · presentation depends only on domain abstractions ·
immutable entities · slivers and `RepaintBoundary` for smooth scroll.

## <img src="docs/icons/stack.svg" width="22" align="top"> Tech stack

`flutter_riverpod` · `just_audio` · `audio_service` · `palette_generator` · `hive` ·
`on_audio_query_pluse` · `connectivity_plus` · `dio` · `cached_network_image` · `shimmer` ·
`google_fonts` — and **FastAPI + yt-dlp + httpx** on the server.

---

## <img src="docs/icons/server.svg" width="22" align="top"> The resolver server (`/server`)

Client-side scraping gets rate-limited and `403`'d per device IP and breaks whenever YouTube
changes. `yt-dlp` is the most robust extractor available, so it runs server-side: one stable IP,
a shared cache, and a Range-seekable audio proxy.

**Docker** is recommended for Synology NAS, VPS, or any Docker host. The image runs **uvicorn with 2 workers** so a cache-hit for the next track can proceed without waiting on the current stream.

```
GET /health
GET /search?q=…&limit=20&filter=tracks|playlists|albums|podcasts
                             → [{id, title, artist, duration, thumbnail, views, kind, url}]
GET /stream?v=VIDEO_ID       → audio bytes · HTTP Range · persistent cache
GET /lyrics?title=&artist=   → synced LRC when lrclib has it, else plain text
GET /playlist?url=…          → {title, uploader, tracks[]} from a playlist / album / mix link
GET /suggest?q=…             → search autocomplete (returns [] on failure, never throws)
GET/PUT /sync                → Firebase-authenticated account backup and restore
```

### Docker Compose (recommended)

The compose file builds the image from `server/Dockerfile` and uses host networking, so the LAN URL the server publishes to the registry is the one the app can reach.

```bash
cd server
cp .env.example .env
# Required in .env: AURORA_SECRET_KEY, FIREBASE_PROJECT_ID
docker compose up -d --build
curl http://localhost:8000/health   # → {"ok":true}
```

| Setting | Value |
|---------|--------|
| Port | **8000** (host networking) |
| `./cache` | Stream cache (audio + SQLite index) |
| `./data` | User sync database (Firebase backup) |

**Synology NAS:** copy the `server/` folder and `.env` to your Docker folder (e.g. `/volume1/docker/aurora`), then run `docker compose up -d --build` via SSH or Container Manager. Point Cloudflare/your reverse proxy at port **8000**.

**Update:** `git pull && docker compose up -d --build`.

Full server docs: [`server/README.md`](server/README.md).

Pushes to `main` that touch `server/**` can also publish an image to Docker Hub via GitHub Actions (see below).

### Local Python (development)

```bash
cd server
cp .env.example .env
# Edit .env to add optional registry settings and choose a cache limit.
# AURORA_CACHE_MAX_BYTES=unlimited keeps cached songs permanently.
python -m pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2 --env-file .env
```

Downloaded tracks are stored under `server/cache` and indexed by YouTube video ID in
SQLite, so later requests and server restarts reuse the same file. The cache is unlimited by
default; set `AURORA_CACHE_MAX_BYTES=10GB` (or another size) to enable LRU eviction.

When signed in with Google, **playlists**, **liked songs**, **recently played**, download
metadata, lyrics, listening stats, and app settings are backed up to the private resolver's
SQLite database (per Firebase user). Liked songs sync immediately on every heart tap; history
and stats upload shortly after playback (and flush before sign-out so nothing is lost). After
reinstall or signing back in, data is restored from the server; signing out clears local
personal data on the device (server copy is kept). Search history stays on-device only.

Verify sync is configured on your server:

```powershell
.\server\scripts\verify_sync.ps1
# Expect HTTP 401 on /sync (auth required). HTTP 503 means FIREBASE_PROJECT_ID is missing — restart the container.
```

For YouTube requests from a datacenter/VPS, create the private proxy list from
the safe example:

```bash
cd server
cp proxies.example.txt proxies.txt
# Replace the example with real proxies, one per line.
```

Accepted formats are `http://user:pass@ip:port`, `user:pass@ip:port`,
`ip:port:user:pass`, and `ip:port`. The resolver chooses a proxy randomly,
rotates to a different one after a failed attempt, and temporarily excludes
failed proxies for 30 minutes. `server/proxies.txt` is gitignored; only the
placeholder-only `server/proxies.example.txt` belongs in GitHub.

## <img src="docs/icons/run.svg" width="22" align="top"> Run the app

Needs **Flutter 3.27+** (`Color.withValues`, AGP-9 toolchain).

First, set up your environment variables:
```bash
cp .env.example .env
# Edit .env with your Vercel registry URL and fallback LAN IP
```

Then run the app:
```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

By default the app resolves the backend URL from a Vercel registry at launch and falls back to
the LAN address in `lib/core/config/app_config.dart`. To pin it to a resolver running next to
you, skip the registry:

```bash
# Android emulator → host machine at 10.0.2.2:8000
flutter run --dart-define-from-file=.env --dart-define=AURORA_LOCAL=true

# physical phone on the same Wi-Fi
flutter run --dart-define-from-file=.env \
            --dart-define=AURORA_LOCAL=true \
            --dart-define=AURORA_API=http://192.168.0.5:8000
```

### Server Security (Secret Key)
To prevent unauthorized access to your FastAPI resolver server:
1. Set `AURORA_SECRET_KEY` in `server/.env`:
   ```bash
   AURORA_SECRET_KEY="your_custom_secret_key"
   ```
2. Pass the key when building or running the Flutter app:
   ```bash
   flutter run --dart-define=AURORA_SECRET_KEY="your_custom_secret_key"
   ```
   Or when building APK:
   ```bash
   flutter build apk --release \
     --dart-define=AURORA_FALLBACK_LAN=http://YOUR_SERVER_IP:8000 \
     --dart-define=AURORA_SECRET_KEY="your_custom_secret_key"
   ```

### Firebase & Google Sign-In Setup
To enable Google Sign-In and Cloud Sync:
1. Place your `google-services.json` in `android/app/`.
2. Optional: set `AURORA_GOOGLE_WEB_CLIENT_ID` in `.env` (Firebase Console → Authentication → Google → **Web client ID**). Without it the app uses the `default_web_client_id` generated from `google-services.json`.
3. Go to **Firebase Console** -> **Project Settings** -> **Your Android App**.
4. Obtain your signing certificate SHA-1 fingerprint:
   ```bash
   cd android && ./gradlew signingReport
   ```
5. Copy the `SHA-1` (and `SHA-256`) fingerprint for your debug/release keystore and add it under **SHA certificate fingerprints** in Firebase Console. *(Without SHA-1 registered in Firebase, Google Sign-In will return an error on mobile devices).*
6. Set `FIREBASE_PROJECT_ID` in `server/.env` to match your Firebase project.

Grant the audio permission for the **On device** tab.

---

## Publish releases

### Android APK

The Android workflow builds an installable APK for every `main` push and pull request. To
publish a version, push a semantic version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions uses the tag as the Android version, creates a GitHub Release with generated
notes, and uploads `Aurora-Music.apk` plus its SHA-256 checksum.

Build locally:

```bash
flutter build apk --release --dart-define-from-file=.env
```

### Docker server image

Pushes to `main` that change `server/**` build and push `<DOCKERHUB_USERNAME>/aurora-server`. The workflow is skipped until Docker Hub publishing is configured in the repository settings:

| Name | Kind | Value |
|------|------|--------|
| `DOCKERHUB_USERNAME` | Actions variable | Docker Hub account that owns the image |
| `DOCKERHUB_TOKEN` | Actions secret | Docker Hub access token (Read & Write) |

You can also trigger **Publish Docker Hub** manually from the Actions tab.

---

## <img src="docs/icons/roadmap.svg" width="22" align="top"> Roadmap

- True crossfade (two overlapping players) — today's is a fade-out into a fade-in, because `just_audio_background` accepts only one player instance.
- Video (MP4) download alongside the current MP3 + lyrics export.
- Brightness drag HUD on the left edge.

---

<div align="center">
Built with Flutter • Spotify-grade soft-dark glass
</div>
