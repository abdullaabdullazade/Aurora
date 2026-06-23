import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/local_store.dart';
import '../../data/datasources/youtube_datasource.dart';
import '../../data/repositories/youtube_music_repository.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/music_repository.dart';

/// Overridden in main() with the initialized instance.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);

final youtubeDatasourceProvider = Provider<YoutubeDatasource>((ref) {
  final ds = YoutubeDatasource();
  ref.onDispose(ds.dispose);
  return ds;
});

/// LIVE repository (YouTube + Hive). Swap here for testing.
final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => YoutubeMusicRepository(
    ref.watch(youtubeDatasourceProvider),
    ref.watch(localStoreProvider),
  ),
);

final trendingProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).trending(),
);

final recentlyPlayedProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).recentlyPlayed(),
);

final downloadsProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(musicRepositoryProvider).downloads(),
);

// --- Search (debounced in the UI) ---------------------------------------
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final q = ref.watch(searchQueryProvider);
  if (q.trim().isEmpty) return const [];
  return ref.watch(musicRepositoryProvider).search(q);
});
