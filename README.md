# 🌌 Aurora Music

Premium media **downloader + player** for Flutter. YouTube-Music feature set, Spotify-grade *soft-dark glassmorphic* UI. Offline-first, 60/120 FPS, Clean Architecture.

> Runs **fully offline out of the box** — seeded with mock data so every screen looks finished. Flip one provider line to go live.

## ✨ What's inside

- **Soft-dark glass design system** — ambient animated radial backdrop (custom painter), real `BackdropFilter` glass, emerald glow accents.
- **Floating frosted nav bar** with morphing emerald pill + haptics.
- **Expandable mini-player** — swipe up / tap to open full player, swipe down to pause, live progress line, Hero artwork transition.
- **Immersive Now-Playing** — blurred album-art backdrop, oversized glowing controls, haptic scrubbing seeker, synced **Lyrics** sheet + drag-reorder **Queue** sheet.
- **Home dashboard** — `CustomScrollView` + `SliverAppBar`, shimmer skeleton carousels, pull-to-refresh.
- **Search** — debounced (350 ms), filter chips, skeleton loaders.
- **Library** — tabbed Downloaded / Playlists / Queue with sub-second offline filter and live download progress (%, MB/s, ETA).

## 🏛 Architecture (Clean Architecture + Riverpod)

```
lib/
├── core/                      # cross-cutting, framework-agnostic
│   ├── theme/                 # colors, spacing, typography, ThemeData + transitions
│   ├── utils/                 # pure formatters (duration, bytes, compact counts)
│   └── audio/                 # audio_service + just_audio handler (background playback)
├── domain/                    # PURE business layer — no Flutter/JSON/IO
│   ├── entities/track.dart
│   └── repositories/          # abstract contracts (Dependency Inversion)
├── data/                      # implements domain contracts
│   ├── datasources/           # youtube_explode_dart wrapper
│   ├── repositories/          # MockMusicRepository (active) | wire real one here
│   └── mock/                  # seed catalogue for offline preview
└── presentation/              # UI only — no business logic in views
    ├── state/                 # Riverpod providers + PlayerController (Notifier)
    ├── widgets/               # Glass, Ambient bg, Artwork, MiniPlayer, controls…
    └── screens/               # root_scaffold, home, search, library, player
```

**Rules enforced:** views hold no business logic; presentation depends only on domain *abstractions*; entities are immutable; `RepaintBoundary` + `ListView.builder`/slivers everywhere for smooth scroll.

## 🚀 Run

```bash
flutter pub get
flutter run
```

Requires Flutter **3.27+** (uses `Color.withValues`). No SDK installed? → https://docs.flutter.dev/get-started/install

## 🔌 Going live (mock → real)

1. Implement `YoutubeMusicRepository` using `data/datasources/youtube_datasource.dart`.
2. In `presentation/state/providers.dart` swap:
   ```dart
   final musicRepositoryProvider =
       Provider<MusicRepository>((ref) => YoutubeMusicRepository(...));
   ```
3. Boot `audio_service` + Hive in `main.dart`; forward `PlayerController` transport
   calls to `AudioPlayerHandler` and replace the simulated ticker with
   `just_audio`'s `positionStream`.
4. Add platform permissions (storage / notifications) and wire `flutter_downloader`.

## 🎨 Design tokens

| Token | Value |
|---|---|
| Void black | `#0B0C10` |
| Base surface | `#121212` |
| Emerald accent | `#1DB954` |
| Neon highlight | `#00E676` |
| Muted text | `#B3B3B3` |
| Glass stroke | `white @ 10%` |

Font: **Plus Jakarta Sans** (`google_fonts`).
