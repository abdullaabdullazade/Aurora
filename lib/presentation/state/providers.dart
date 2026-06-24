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
