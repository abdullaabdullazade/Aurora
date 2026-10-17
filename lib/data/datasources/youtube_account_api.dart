import 'package:dio/dio.dart';
import '../../core/config/app_config.dart';
import '../../domain/entities/track.dart';

/// Fetches personalized YouTube data through the private resolver.
class YoutubeAccountApi {
  YoutubeAccountApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBase,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              headers: AppConfig.apiSecretKey.isNotEmpty
                  ? {'x-api-key': AppConfig.apiSecretKey}
                  : null,
            ));

  final Dio _dio;

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

  Future<List<Track>> fetchSubscriptionFeed(String accessToken,
      {int limit = 20}) async {
    final res = await _dio.get(
      '/youtube/subscriptions',
      queryParameters: {'limit': limit},
      options: Options(
        headers: {'x-google-access-token': accessToken},
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final list = (res.data as List).cast<Map<String, dynamic>>();
    return list.map(_fromJson).toList(growable: false);
  }
}
