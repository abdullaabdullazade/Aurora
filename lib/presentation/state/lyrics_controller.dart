import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../domain/entities/lyric_line.dart';
import 'player_controller.dart';
import 'providers.dart';

LyricsResult _parse(Map<dynamic, dynamic> data) {
  final synced = ((data['synced'] as List?) ?? [])
      .map((e) => LyricLine(
            (e['time'] as num).toDouble(),
            e['text'] as String,
          ))
      .toList();
  return LyricsResult(
    synced: synced,
    plain: (data['plain'] as String?) ?? '',
    found: data['found'] == true || synced.isNotEmpty,
  );
}

final _dio = Dio(BaseOptions(
  baseUrl: AppConfig.apiBase,
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 15),
));

/// Lyrics for the current track. Uses offline-saved lyrics first (downloaded
/// alongside the track), then falls back to the lrclib resolver.
final lyricsProvider = FutureProvider.autoDispose<LyricsResult>((ref) async {
  final track = ref.watch(playerControllerProvider.select((s) => s.current));
  if (track == null) return const LyricsResult();

  // Offline cache (saved when the track was downloaded).
  final cached = ref.read(localStoreProvider).lyrics(track.id);
  if (cached != null) return _parse(cached);

  final res = await _dio.get('/lyrics', queryParameters: {
    'title': track.title,
    'artist': track.artist,
    'duration': track.duration.inSeconds,
  });
  return _parse(res.data as Map<dynamic, dynamic>);
});
