import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';
import '../../domain/entities/track.dart';
import 'providers.dart';

/// Downloads a track's audio (m4a) through the resolver proxy into local
/// storage, indexes it for offline play, and saves its lyrics alongside.
/// State maps trackId -> progress (0..1) for in-flight downloads.
class DownloadController extends Notifier<Map<String, double>> {
  final Dio _dio = Dio();

  @override
  Map<String, double> build() => {};

  bool isDownloading(String id) => state.containsKey(id);

  Future<void> download(Track track) async {
    if (track.localPath != null || state.containsKey(track.id)) return;
    state = {...state, track.id: 0};
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/aurora');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final path = '${folder.path}/${track.id}.m4a';

      await _dio.download(
        '${AppConfig.apiBase}/stream?v=${track.id}',
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            state = {...state, track.id: received / total};
          }
        },
      );

      final store = ref.read(localStoreProvider);
      await store.saveDownload(track.copyWith(localPath: path));

      // Best-effort: cache lyrics for offline display.
      try {
        final res = await _dio.get(
          '${AppConfig.apiBase}/lyrics',
          queryParameters: {
            'title': track.title,
            'artist': track.artist,
            'duration': track.duration.inSeconds,
          },
        );
        if (res.data is Map) {
          await store.saveLyrics(
              track.id, Map<String, dynamic>.from(res.data as Map));
        }
      } catch (_) {/* lyrics optional */}

      ref.invalidate(downloadsProvider);
    } finally {
      final next = {...state}..remove(track.id);
      state = next;
    }
  }
}

final downloadControllerProvider =
    NotifierProvider<DownloadController, Map<String, double>>(
        DownloadController.new);
