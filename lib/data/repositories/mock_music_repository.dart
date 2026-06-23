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
    return _delayed(q.isEmpty ? MockTracks.all : hits, 400);
  }

  @override
  Future<List<Track>> trending() => _delayed(MockTracks.trending);

  @override
  Future<List<Track>> recentlyPlayed() => _delayed(MockTracks.recent);

  @override
  Future<List<Track>> downloads() => _delayed(MockTracks.downloads, 200);

  @override
  Future<Uri> resolveStream(Track track, {bool audioOnly = true}) =>
      // Placeholder playable asset; real impl uses YoutubeDatasource.
      _delayed(Uri.parse('asset:///audio/${track.id}.mp3'), 120);
}
