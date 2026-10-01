import 'package:dio/dio.dart';
import '../../core/config/app_config.dart';
import '../../core/db/local_store.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/music_repository.dart';

/// Talks to the FastAPI + yt-dlp resolver. All YouTube extraction happens
/// server-side, so the app never gets rate-limited / 403'd by googlevideo.
class ApiMusicRepository implements MusicRepository {
  final Dio _dio;
  final LocalStore _store;
  final Map<String, List<Track>> _cache = {};

  ApiMusicRepository(this._store, [Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBase,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              headers: AppConfig.apiSecretKey.isNotEmpty
                  ? {'x-api-key': AppConfig.apiSecretKey}
                  : null,
            ));

  Track _fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    final kind = Track.kindFrom(j['kind']);
    final browse = (j['url'] as String?)?.isNotEmpty == true
        ? j['url'] as String
        : (j['browseUrl'] as String?);
    final thumb = (j['thumbnail'] as String?) ?? '';
    return Track(
      id: id,
      title: (j['title'] as String?) ?? 'Unknown',
      artist: (j['artist'] as String?) ?? 'Unknown',
      artworkUrl: thumb.isNotEmpty
          ? thumb
          : (kind == TrackKind.track
              ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg'
              : ''),
      duration: Duration(seconds: (j['duration'] as num?)?.toInt() ?? 0),
      plays: (j['views'] as num?)?.toInt() ?? 0,
      accent: Track.accentFor(id),
      channelUrl: (j['channelUrl'] as String?)?.isNotEmpty == true
          ? j['channelUrl'] as String
          : null,
      kind: kind,
      browseUrl: browse,
    );
  }

  Future<List<Track>> _search(String query, int limit,
      {String filter = 'tracks', bool playableOnly = false}) async {
    final res = await _dio.get('/search', queryParameters: {
      'q': query,
      'limit': limit,
      'filter': filter,
    });
    final list = (res.data as List).cast<Map<String, dynamic>>();
    return list
        .where((j) => !playableOnly || _isPlayable(j))
        .map(_fromJson)
        .toList(growable: false);
  }

  /// Live streams never finish downloading on the resolver, so they would
  /// spin forever when tapped. Search results omit is_live on older servers;
  /// a zero duration on a video is the same signal there.
  static bool _isPlayable(Map<String, dynamic> j) {
    if (j['live'] == true) return false;
    final kind = Track.kindFrom(j['kind']);
    if (kind != TrackKind.track) return true;
    return ((j['duration'] as num?)?.toInt() ?? 0) > 0;
  }

  static const _searchCacheTtl = Duration(minutes: 30);
  final Map<String, ({DateTime at, List<Track> tracks})> _searchCache = {};

  @override
  Future<List<Track>> search(String query, {String filter = 'tracks'}) {
    // Tracks: bias toward music. Collections: pass query through unchanged
    // (server appends album/podcast when needed).
    final q = filter == 'tracks' ? '$query music' : query;
    return _search(q, 25, filter: filter);
  }

  @override
  Future<List<Track>> searchTracks(String query, {int limit = 25}) async {
    final key = '$query|$limit';
    final hit = _searchCache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _searchCacheTtl) {
      return hit.tracks;
    }
    final tracks = await _search(query, limit, playableOnly: true);
    _searchCache[key] = (at: DateTime.now(), tracks: tracks);
    return tracks;
  }

  @override
  Future<List<Track>> trending({bool refresh = false}) async {
    if (refresh) _cache.remove('trending');
    final cached = _cache['trending'];
    if (cached != null) return cached;

    final year = DateTime.now().year;
    final queries = [
      'trending music $year',
      'new music releases $year',
      'popular songs today',
    ];
    final q = queries[DateTime.now().day % queries.length];
    return _cache['trending'] = await _search(q, 20, playableOnly: true);
  }

  @override
  Future<List<Track>> topCharts() async {
    final cached = _cache['topCharts'];
    if (cached != null) return cached;

    try {
      final url =
          'https://www.youtube.com/playlist?list=${AppConfig.topChartsPlaylistId}';
      final res = await importPlaylist(url);
      if (res.tracks.isNotEmpty) {
        return _cache['topCharts'] =
            res.tracks.take(25).toList(growable: false);
      }
    } catch (_) {
      // Playlist unavailable on resolver — fall back to search below.
    }

    return _cache['topCharts'] =
        await _search('top charts this week', 25, playableOnly: true);
  }

  @override
  void invalidateRecommendationCaches() {
    _cache.remove('trending');
    _cache.remove('topCharts');
    _searchCache.clear();
  }

  @override
  Future<List<Track>> recentlyPlayed() async => _store.recents();

  @override
  Future<List<Track>> downloads() async => _store.downloads();

  @override
  Future<Uri> resolveStream(Track track, {bool audioOnly = true}) async {
    final secret = AppConfig.apiSecretKey;
    final keyParam = secret.isNotEmpty ? '&key=$secret' : '';
    return Uri.parse('${AppConfig.apiBase}/stream?v=${track.id}$keyParam');
  }

  @override
  Future<({String title, List<Track> tracks})> importPlaylist(
      String url) async {
    final res = await _dio.get('/playlist',
        queryParameters: {'url': url},
        options: Options(receiveTimeout: const Duration(seconds: 90)));
    final map = res.data as Map<String, dynamic>;
    final list = (map['tracks'] as List).cast<Map<String, dynamic>>();
    return (
      title: (map['title'] as String?) ?? 'Imported playlist',
      tracks: list.map(_fromJson).toList(growable: false),
    );
  }

  @override
  Future<List<String>> suggest(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final res = await _dio.get('/suggest',
          queryParameters: {'q': query},
          options: Options(receiveTimeout: const Duration(seconds: 6)));
      return (res.data as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }
}
