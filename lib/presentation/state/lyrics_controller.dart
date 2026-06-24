import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../domain/entities/lyric_line.dart';
import 'player_controller.dart';

final _dio = Dio(BaseOptions(
  baseUrl: AppConfig.apiBase,
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 15),
));

/// Real lyrics for the currently playing track (lrclib via the resolver).
final lyricsProvider = FutureProvider.autoDispose<LyricsResult>((ref) async {
  final track = ref.watch(playerControllerProvider.select((s) => s.current));
  if (track == null) return const LyricsResult();

  final res = await _dio.get('/lyrics', queryParameters: {
    'title': track.title,
    'artist': track.artist,
    'duration': track.duration.inSeconds,
  });
  final data = res.data as Map<String, dynamic>;
  final synced = ((data['synced'] as List?) ?? [])
      .map((e) => LyricLine(
            (e['time'] as num).toDouble(),
            e['text'] as String,
          ))
      .toList();
  return LyricsResult(
    synced: synced,
    plain: (data['plain'] as String?) ?? '',
    found: data['found'] == true,
  );
});
