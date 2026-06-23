import '../../core/db/local_store.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/music_repository.dart';
import '../datasources/youtube_datasource.dart';

/// Live repository: search/streams from YouTube, recents/downloads from Hive.
class YoutubeMusicRepository implements MusicRepository {
  final YoutubeDatasource _yt;
  final LocalStore _store;

  YoutubeMusicRepository(this._yt, this._store);

  // Simple in-memory cache so re-entering Home doesn't re-hit the network.
  final Map<String, List<Track>> _cache = {};

  @override
  Future<List<Track>> search(String query, {String filter = 'tracks'}) {
    // Bias results toward music for the default filter.
    final q = filter == 'videos' ? query : '$query music';
    return _yt.search(q);
  }

  @override
  Future<List<Track>> trending() async =>
      _cache['trending'] ??= await _yt.search('trending music 2026');

  @override
  Future<List<Track>> recentlyPlayed() async => _store.recents();

  @override
  Future<Uri> resolveStream(Track track, {bool audioOnly = true}) =>
      _yt.audioStreamUrl(track.id);

  @override
  Future<List<Track>> downloads() async => _store.downloads();
}
