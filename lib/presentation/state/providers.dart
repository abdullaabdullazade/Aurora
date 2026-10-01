import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/local_store.dart';
import '../../data/datasources/youtube_account_api.dart';
import '../../data/repositories/api_music_repository.dart';
import '../../domain/entities/recent_playlist.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/music_repository.dart';
import 'auth_controller.dart';
import 'favorites_controller.dart';

/// Overridden in main() with the initialized instance.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);

/// Incremented after a server sync changes Hive so state notifiers rebuild.
final syncRevisionProvider = StateProvider<int>((ref) => 0);

/// LIVE repository: FastAPI + yt-dlp resolver server (robust, no client 403s).
final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => ApiMusicRepository(ref.watch(localStoreProvider)),
);

final trendingProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).trending(),
);

final youtubeAccountApiProvider = Provider<YoutubeAccountApi>(
  (ref) => YoutubeAccountApi(),
);

/// Personalized picks from listening history, liked songs, or global trends.
/// History is read, not watched: every started track updates stats and
/// recents, and rebuilding here would re-run the searches and reshuffle the
/// list under the user's finger. Pull-to-refresh and account sync rebuild it.
final forYouProvider = FutureProvider<List<Track>>((ref) async {
  ref.watch(syncRevisionProvider);
  final repo = ref.watch(musicRepositoryProvider);
  final stats = ref.read(listeningStatsProvider);
  final favorites = ref.read(favoritesProvider);
  final recentIds =
      ref.read(localStoreProvider).recents().map((t) => t.id).toSet();

  final artistCounts = <String, int>{};
  for (final row in stats) {
    final artist = row.track.artist.trim();
    if (artist.isEmpty || artist == 'Unknown') continue;
    artistCounts[artist] = (artistCounts[artist] ?? 0) + row.count;
  }
  final topArtists = artistCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  var artists = topArtists.take(3).map((e) => e.key).toList();

  if (artists.isEmpty && favorites.isNotEmpty) {
    artists = favorites.map((t) => t.artist.trim()).where((a) {
      return a.isNotEmpty && a != 'Unknown';
    }).toSet().take(3).toList();
  }

  if (artists.isEmpty) {
    return _filterRecommendations(await repo.trending(), recentIds);
  }

  final merged = <Track>[];
  final seen = <String>{};
  for (final artist in artists) {
    final tracks =
        await repo.searchTracks('$artist music', limit: 8);
    for (final track in tracks) {
      if (seen.add(track.id)) merged.add(track);
    }
  }
  return _filterRecommendations(merged, recentIds);
});

/// For-you suggestions that are not already downloaded offline.
final quickDownloadsProvider = FutureProvider<List<Track>>((ref) async {
  ref.watch(syncRevisionProvider);
  final forYou = await ref.watch(forYouProvider.future);
  final downloadedIds = ref
      .watch(localStoreProvider)
      .downloads()
      .map((t) => t.id)
      .toSet();
  return forYou
      .where((t) => !downloadedIds.contains(t.id))
      .take(12)
      .toList(growable: false);
});

/// Recent uploads from YouTube channels the user subscribes to.
final fromYourChannelsProvider = FutureProvider<List<Track>>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const [];

  final token = await ref.read(authControllerProvider).youtubeAccessToken();
  if (token == null) return const [];

  return ref
      .read(youtubeAccountApiProvider)
      .fetchSubscriptionFeed(token, limit: 20);
});

List<Track> _filterRecommendations(List<Track> tracks, Set<String> excludeIds,
    {int limit = 24}) {
  final out = <Track>[];
  final seen = <String>{};
  for (final track in tracks) {
    if (excludeIds.contains(track.id)) continue;
    if (seen.add(track.id)) out.add(track);
    if (out.length >= limit) break;
  }
  return out;
}

final recentlyPlayedProvider = FutureProvider<List<Track>>(
  (ref) {
    ref.watch(syncRevisionProvider);
    return ref.watch(musicRepositoryProvider).recentlyPlayed();
  },
);

/// Up to 4 MRU playlists for the Home quick-access grid.
final recentPlaylistsProvider = Provider<List<RecentPlaylist>>((ref) {
  ref.watch(syncRevisionProvider);
  return ref.watch(localStoreProvider).recentPlaylists();
});

final topChartsProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).topCharts(),
);

/// Tracks for an artist (real artist APIs aren't available client-side, so we
/// search the artist name and surface their top results).
final artistTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, name) async {
  if (name.trim().isEmpty) return const [];
  return ref.watch(musicRepositoryProvider).search(name);
});

final downloadsProvider = FutureProvider<List<Track>>(
  (ref) {
    ref.watch(syncRevisionProvider);
    return ref.watch(musicRepositoryProvider).downloads();
  },
);

/// Selected bottom-nav tab (0 Home · 1 Search · 2 Library). Lets any screen
/// switch tabs (e.g. Home's search button).
final navIndexProvider = StateProvider<int>((ref) => 0);

/// Selected Library tab (0 Playlists · 1 On device · 2 Downloaded · 3 Queue).
/// Lets a download notification jump straight to the Queue.
final libraryTabProvider = StateProvider<int>((ref) => 0);

// --- Search (debounced in the UI) ---------------------------------------
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Active search chip: tracks | playlists | albums | podcasts.
final searchFilterProvider = StateProvider<String>((ref) => 'tracks');

final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final q = ref.watch(searchQueryProvider);
  final filter = ref.watch(searchFilterProvider);
  if (q.trim().isEmpty) return const [];
  return ref.watch(musicRepositoryProvider).search(q, filter: filter);
});

/// Autocomplete for the current query. Separate from [searchResultsProvider]
/// so suggestions can appear while the (slower) result search is still running.
final searchSuggestionsProvider =
    FutureProvider.family<List<String>, String>((ref, q) async {
  if (q.trim().length < 2) return const [];
  return ref.watch(musicRepositoryProvider).suggest(q);
});

/// Past queries, newest first. Invalidated whenever the history is written.
final searchHistoryProvider = Provider<List<String>>(
  (ref) {
    ref.watch(syncRevisionProvider);
    return ref.watch(localStoreProvider).searchHistory();
  },
);

// --- Listening stats -----------------------------------------------------
/// A track plus how it has actually been listened to.
typedef PlayStat = ({Track track, int count, int secondsPlayed});

final listeningStatsProvider = Provider<List<PlayStat>>((ref) {
  ref.watch(syncRevisionProvider);
  return ref.watch(localStoreProvider).stats().map((row) {
    return (
      track: Track.fromJson(row),
      count: (row['count'] as num?)?.toInt() ?? 0,
      secondsPlayed: (row['seconds_played'] as num?)?.toInt() ?? 0,
    );
  }).toList();
});

/// Keep every liked song available offline, downloading in the background.
class AutoDownloadFavoritesController extends Notifier<bool> {
  static const _key = 'auto_download_favorites';

  @override
  bool build() {
    ref.watch(syncRevisionProvider);
    return ref.watch(localStoreProvider).flag(_key);
  }

  Future<void> set(bool value) async {
    await ref.read(localStoreProvider).setFlag(_key, value);
    state = value;
  }
}

final autoDownloadFavoritesProvider =
    NotifierProvider<AutoDownloadFavoritesController, bool>(
        AutoDownloadFavoritesController.new);

/// When on, new downloads start only on Wi-Fi (default off).
class WifiOnlyDownloadsController extends Notifier<bool> {
  static const _key = 'wifi_only_downloads';

  @override
  bool build() {
    ref.watch(syncRevisionProvider);
    return ref.watch(localStoreProvider).flag(_key);
  }

  Future<void> set(bool value) async {
    await ref.read(localStoreProvider).setFlag(_key, value);
    state = value;
  }
}

final wifiOnlyDownloadsProvider =
    NotifierProvider<WifiOnlyDownloadsController, bool>(
        WifiOnlyDownloadsController.new);

/// Fade the outgoing track out while the next one fades in.
class CrossfadeController extends Notifier<bool> {
  static const _key = 'crossfade';

  @override
  bool build() {
    ref.watch(syncRevisionProvider);
    return ref.watch(localStoreProvider).flag(_key);
  }

  Future<void> set(bool value) async {
    await ref.read(localStoreProvider).setFlag(_key, value);
    state = value;
  }
}

final crossfadeProvider =
    NotifierProvider<CrossfadeController, bool>(CrossfadeController.new);

/// Length of that blend, in seconds.
class CrossfadeSecondsController extends Notifier<int> {
  static const _key = 'crossfade_seconds';

  @override
  int build() {
    ref.watch(syncRevisionProvider);
    return (ref.watch(localStoreProvider).number(_key) ?? 6).clamp(2, 12);
  }

  Future<void> set(int value) async {
    final v = value.clamp(2, 12);
    await ref.read(localStoreProvider).setNumber(_key, v);
    state = v;
  }
}

final crossfadeSecondsProvider =
    NotifierProvider<CrossfadeSecondsController, int>(
        CrossfadeSecondsController.new);

/// Resume the last track and position after a cold start (paused).
class ResumePlaybackController extends Notifier<bool> {
  static const _key = 'resume_playback';

  @override
  bool build() {
    ref.watch(syncRevisionProvider);
    return ref.watch(localStoreProvider).flag(_key, fallback: true);
  }

  Future<void> set(bool value) async {
    final store = ref.read(localStoreProvider);
    await store.setFlag(_key, value);
    if (!value) await store.clearPlaybackSession();
    state = value;
  }
}

final resumePlaybackProvider =
    NotifierProvider<ResumePlaybackController, bool>(
        ResumePlaybackController.new);
