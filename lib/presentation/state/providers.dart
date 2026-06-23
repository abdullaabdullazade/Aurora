import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/mock_music_repository.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/music_repository.dart';

/// Swap this single line to go live (YoutubeMusicRepository()).
final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => MockMusicRepository(),
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

/// Search query (debounced in the UI), and its results.
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final q = ref.watch(searchQueryProvider);
  if (q.trim().isEmpty) return const [];
  return ref.watch(musicRepositoryProvider).search(q);
});
