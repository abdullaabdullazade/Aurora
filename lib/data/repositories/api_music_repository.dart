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
    return Track(
      id: id,
      title: (j['title'] as String?) ?? 'Unknown',
      artist: (j['artist'] as String?) ?? 'Unknown',
      artworkUrl: (j['thumbnail'] as String?) ??
          'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      duration: Duration(seconds: (j['duration'] as num?)?.toInt() ?? 0),
      plays: (j['views'] as num?)?.toInt() ?? 0,
      accent: Track.accentFor(id),
      channelUrl: (j['channelUrl'] as String?)?.isNotEmpty == true
          ? j['channelUrl'] as String
          : null,
    );
  }

  Future<List<Track>> _search(String query, int limit) async {
    final res = await _dio.get('/search',
        queryParameters: {'q': query, 'limit': limit});
    final list = (res.data as List).cast<Map<String, dynamic>>();
    return list.map(_fromJson).toList(growable: false);
  }

  @override
  Future<List<Track>> search(String query, {String filter = 'tracks'}) {
    final q = filter == 'videos' ? query : '$query music';
    return _search(q, 25);
  }

  @override
  Future<List<Track>> trending() async =>
      _cache['trending'] ??= await _search('trending music 2026', 20);

  @override
  Future<List<Track>> recentlyPlayed() async => _store.recents();

  @override
  Future<List<Track>> downloads() async => _store.downloads();

  /// Streamed through the resolver proxy (clean headers → no CDN 403).
  /// Direct on-device play 403s in ExoPlayer; the proxy is the reliable path.
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
