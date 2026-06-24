<div align="center">

# 🌌 Aurora Music

### Premium media downloader & player — YouTube-Music power, Spotify-grade soft-dark glass design.

**Live** · real YouTube search & streaming · on-device library · playlists · offline-first · 60/120 FPS

</div>

---

> Flutter front-end + a **Python (FastAPI + yt-dlp) resolver server**. All YouTube
> extraction happens server-side and audio is range-proxied, so the app never gets
> the `403` / rate-limiting that pure client-side scraping hits. Verified playing on
> Android.

---

## ✨ Features — everything in the app

### 🔎 Discovery & search
- **Real YouTube search** via the resolver server (debounced 350 ms, filter chips: Tracks / Videos / Playlists / Albums).
- **Home dashboard**: `CustomScrollView` + cross-fading `SliverAppBar`, horizontal carousels for **Trending now**, **Recently played**, **Quick downloads**.
- **Header cluster**: brand wordmark, search, notifications, avatar.
- **Shimmer skeletons** (dark/emerald) shaped like the real cards while loading — no bare spinners.
- **Retry-able error state** if the server is unreachable (no ugly "couldn't load" text).

### ▶️ Playback (rock-solid)
- Streams the resolved audio through the server proxy (`audio/mp4`, HTTP **Range** → seekable).
- **Dual source**: remote YouTube *and* local device files play through the same engine (`just_audio`).
- Queue with **shuffle**, **repeat one/all**, **drag-to-reorder** (Up-Next sheet).
- Records **Recently played** automatically.

### 🎚 The "Ultimate" Now-Playing screen
- Full-screen immersive layout; background = the album art **blurred** + a color veil.
- **Dynamic ambient color** extracted from the artwork with `palette_generator` — the whole UI re-tints to match the track.
- **Album-art particle pulse**: a lightweight canvas of orbiting particles + a breathing ring that speeds up while playing.
- **Waveform seeker**: custom-painted audio bars as the progress/scrubber — elastic bump near the finger + a haptic tick as you cross each bar.
- **Volume drag HUD**: drag the right edge vertically → a thin glass HUD shows the level (no system volume UI).
- **Sleep timer** (5–60 min) with a **10-second volume fade-out** before it pauses — never an abrupt stop.
- Oversized glowing transport keys, animated heart, **Lyrics** & **Queue** sheets.

### 📚 Library
- Tabs: **Playlists · On device · Downloaded · Queue**.
- **Playlists**: create / delete, detail screen with play-all + swipe-to-remove, "add to playlist" from any track.
- **Liked Songs**: persistent favorites, animated heart toggle (haptic).

### 📱 On-device music (offline-first)
- Scans the device library via MediaStore (`on_audio_query_pluse`).
- **Grouped by folder**, sorted by size; per-folder **show/hide** (e.g. hide ringtones, keep *Telegram Music*) — persisted.
- **Play all visible**, per-folder detail screen, embedded MediaStore artwork.

### 🌐 Offline Sanctuary
- Live connectivity watch (`connectivity_plus`).
- When offline: non-downloaded items **fade to 40 % and become unclickable**, and a **breathing "Offline Sanctuary"** pill appears under the header.

### 💧 Micro-interactions
- **Aurora pull-to-refresh**: a glowing orb that scales/pulses with overscroll distance (custom, not the Material spinner).
- `AnimatedSwitcher` ~300 ms cross-fades; custom fade-up page transitions; `HapticFeedback` on play/pause, nav, scrub, toggles.
- Glassmorphism everywhere via real `BackdropFilter`, each surface wrapped in `RepaintBoundary`.

---

## 🎨 Design system — "Soft Dark / Glass"

| Token | Value | Use |
|---|---|---|
| Void black | `#0B0C10` | deepest background |
| Base | `#121212` | primary surface |
| Elevated | `#181818` / `#242424` | cards / hovered |
| Emerald | `#1DB954` | accent, playback |
| Neon | `#00E676` | highlights, glow |
| Text | `#FFFFFF` / `#B3B3B3` / `#6E6E6E` | primary / muted / tertiary |
| Glass stroke | `white @ 10 %` | hairline borders |

- **Type**: Plus Jakarta Sans (`google_fonts`) — tight, high-contrast scale (`AppType`).
- **Spacing/radii**: 4-pt scale + shared radii (`Sp`, `Radii`).
- **Ambient**: animated multi-blob radial gradient (`AmbientBackground`) that follows the active track's color.
- **Motion**: soft fade-through + slight upward slide on route push (`AppTheme`).

---

## 🏛 Architecture — Clean Architecture + Riverpod

```
lib/
├── core/
│   ├── theme/         colors · type · spacing · ThemeData + transitions
│   ├── config/        AppConfig (server base URL)
│   ├── audio/         audio_service handler (background playback scaffold)
│   ├── db/            LocalStore (Hive: playlists, recents, favorites, settings)
│   └── utils/         pure formatters
├── domain/            entities (Track, Playlist) + repository contracts
├── data/
│   └── repositories/  ApiMusicRepository (server) · MockMusicRepository
└── presentation/
    ├── state/         Riverpod providers + controllers
    │                  (player, playlists, favorites, device music, connectivity)
    ├── widgets/       Glass · AmbientBackground · Artwork · WaveformSeeker ·
    │                  AlbumPulse · AuroraRefresh · MiniPlayer · nav bar · …
    └── screens/       home · search · library (+device, playlist, folder) · player
```

**Rules:** no business logic in views · presentation depends only on domain abstractions · immutable entities · `ListView.builder`/slivers + `RepaintBoundary` for smooth scroll.

## 🧰 Tech stack
`flutter_riverpod` · `just_audio` · `audio_service` · `palette_generator` · `hive` ·
`on_audio_query_pluse` · `connectivity_plus` · `dio` · `cached_network_image` · `shimmer` ·
`google_fonts` — and **FastAPI + yt-dlp + httpx** (server).

---

## 🐍 The resolver server (`/server`)

Why: client-side scraping gets rate-limited / `403`'d per device and breaks on YouTube
changes. yt-dlp is the most robust extractor; running it server-side gives one stable
IP, caching, and a clean range-proxy so the app never talks to googlevideo directly.

```
GET /health
GET /search?q=...&limit=20   → [{id,title,artist,duration,thumbnail,views}]
GET /stream?v=VIDEO_ID       → audio bytes (HTTP Range supported, 30-min URL cache)
```

Run it:
```bash
cd server
python -m pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

## 🚀 Run the app

```bash
flutter pub get
flutter run            # needs Flutter 3.27+ (Color.withValues, AGP-9 toolchain)
```

- **Android emulator** reaches the host server at `http://10.0.2.2:8000` (already configured).
- **Physical phone** (same Wi-Fi): set `lib/core/config/app_config.dart` →
  `apiBase = 'http://<your-PC-LAN-IP>:8000'`.
- Grant the audio permission for the **On device** tab.

## 🗺 Roadmap
- Full background playback + lock-screen/notification via `audio_service` (handler scaffolded).
- Real download engine (m4a export) + offline file management.
- Brightness drag HUD (left edge), synced `.lrc` lyrics, equalizer.

---

<div align="center">
Built with Flutter • Spotify-grade soft-dark glass • 🌌
</div>
