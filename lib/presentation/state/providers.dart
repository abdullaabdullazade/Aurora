import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/local_store.dart';
import '../../data/repositories/api_music_repository.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/music_repository.dart';

/// Overridden in main() with the initialized instance.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);

/// LIVE repository: FastAPI + yt-dlp resolver server (robust, no client 403s).
final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => ApiMusicRepository(ref.watch(localStoreProvider)),
);

final trendingProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).trending(),
);

final recentlyPlayedProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).recentlyPlayed(),
);

final topChartsProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).search('top charts this week'),
);

/// Tracks for an artist (real artist APIs aren't available client-side, so we
/// search the artist name and surface their top results).
final artistTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, name) async {
  if (name.trim().isEmpty) return const [];
  return ref.watch(musicRepositoryProvider).search(name);
});

final downloadsProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).downloads(),
);

/// Selected bottom-nav tab (0 Home · 1 Search · 2 Library). Lets any screen
/// switch tabs (e.g. Home's search button).
final navIndexProvider = StateProvider<int>((ref) => 0);

/// Selected Library tab (0 Playlists · 1 On device · 2 Downloaded · 3 Queue).
/// Lets a download notification jump straight to the Queue.
final libraryTabProvider = StateProvider<int>((ref) => 0);

// --- Search (debounced in the UI) ---------------------------------------
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final q = ref.watch(searchQueryProvider);
  if (q.trim().isEmpty) return const [];
  return ref.watch(musicRepositoryProvider).search(q);
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
  (ref) => ref.watch(localStoreProvider).searchHistory(),
);

// --- Listening stats -----------------------------------------------------
/// A track plus how it has actually been listened to.
typedef PlayStat = ({Track track, int count, int secondsPlayed});

final listeningStatsProvider = Provider<List<PlayStat>>((ref) {
  return ref.watch(localStoreProvider).stats().map((row) {
    return (
      track: Track.fromJson(row),
      count: (row['count'] as num?)?.toInt() ?? 0,
      secondsPlayed: (row['seconds_played'] as num?)?.toInt() ?? 0,
    );
  }).toList();
});

/// Continuous playback at the end of a finite queue (radio is always on when
/// explicitly started; this is the implicit case).
class AutoplayController extends Notifier<bool> {
  static const _key = 'autoplay';

  @override
  bool build() =>
      ref.watch(localStoreProvider).flag(_key, fallback: true);

  Future<void> set(bool value) async {
    await ref.read(localStoreProvider).setFlag(_key, value);
    state = value;
  }
}

final autoplayProvider =
    NotifierProvider<AutoplayController, bool>(AutoplayController.new);

/// Keep every liked song available offline, downloading in the background.
class AutoDownloadFavoritesController extends Notifier<bool> {
  static const _key = 'auto_download_favorites';

  @override
  bool build() => ref.watch(localStoreProvider).flag(_key);

  Future<void> set(bool value) async {
    await ref.read(localStoreProvider).setFlag(_key, value);
    state = value;
  }
}

final autoDownloadFavoritesProvider =
    NotifierProvider<AutoDownloadFavoritesController, bool>(
        AutoDownloadFavoritesController.new);

/// Fade the outgoing track out while the next one fades in.
class CrossfadeController extends Notifier<bool> {
  static const _key = 'crossfade';

  @override
  bool build() => ref.watch(localStoreProvider).flag(_key);

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
  int build() =>
      (ref.watch(localStoreProvider).number(_key) ?? 6).clamp(2, 12);

  Future<void> set(int value) async {
    final v = value.clamp(2, 12);
    await ref.read(localStoreProvider).setNumber(_key, v);
    state = v;
  }
}

final crossfadeSecondsProvider =
    NotifierProvider<CrossfadeSecondsController, int>(
        CrossfadeSecondsController.new);
