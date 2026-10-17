import '../../domain/entities/track.dart';
import '../../domain/repositories/music_repository.dart';
import '../mock/mock_tracks.dart';

/// In-memory repository for development / offline preview.
/// Adds realistic latency so shimmer/skeleton states are visible.
class MockMusicRepository implements MusicRepository {
  Future<T> _delayed<T>(T value, [int ms = 650]) =>
      Future.delayed(Duration(milliseconds: ms), () => value);

  @override
  Future<List<Track>> search(String query, {String filter = 'tracks'}) {
    final q = query.trim().toLowerCase();
    final hits = MockTracks.all
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q))
        .toList();
    final base = q.isEmpty ? MockTracks.all : hits;
    if (filter == 'tracks') return _delayed(base, 400);
    // Fake a couple of collection hits for UI preview.
    return _delayed(
      base
          .take(3)
          .map((t) => t.copyWith(
                kind: switch (filter) {
                  'albums' => TrackKind.album,
                  'podcasts' => TrackKind.podcast,
                  _ => TrackKind.playlist,
                },
                browseUrl: 'https://www.youtube.com/playlist?list=${t.id}',
              ))
          .toList(),
      400,
    );
  }

  @override
  Future<List<Track>> trending({bool refresh = false}) =>
      _delayed(MockTracks.trending);

  @override
  Future<List<Track>> searchTracks(String query, {int limit = 25}) =>
      search(query);

  @override
  Future<List<Track>> searchPlaylists(String query, {int limit = 10}) =>
      search(query, filter: 'playlists');

  @override
  Future<List<Track>> topCharts() => _delayed(MockTracks.trending);

  @override
  void invalidateRecommendationCaches() {}

  @override
  Future<List<Track>> recentlyPlayed() => _delayed(MockTracks.recent);

  @override
  Future<List<Track>> downloads() => _delayed(MockTracks.downloads, 200);

  @override
  Future<Uri> resolveStream(Track track, {bool audioOnly = true}) =>
      // Placeholder playable asset; real impl uses YoutubeDatasource.
      _delayed(Uri.parse('asset:///audio/${track.id}.mp3'), 120);

  @override
  Future<({String title, List<Track> tracks})> importPlaylist(String url) =>
      _delayed((title: 'Imported playlist', tracks: MockTracks.all), 600);

  @override
  Future<List<String>> suggest(String query) => _delayed(
        MockTracks.all
            .map((t) => t.title)
            .where((t) =>
                t.toLowerCase().contains(query.trim().toLowerCase()))
            .take(8)
            .toList(),
        150,
      );
}
