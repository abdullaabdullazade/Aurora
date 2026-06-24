import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/notifications/notification_service.dart';
import '../../domain/entities/track.dart';
import 'providers.dart';

/// Downloads a track's audio (m4a) + lyrics into local storage and indexes it
/// for offline play. State maps trackId -> progress (0..1). Shows a live
/// progress notification with a Cancel action; reports done / error.
typedef DownloadJob = ({Track track, double progress});

class DownloadController extends Notifier<Map<String, DownloadJob>> {
  final Dio _dio = Dio();
  final Map<String, CancelToken> _tokens = {};

  @override
  Map<String, DownloadJob> build() {
    NotificationService.instance.onDownloadCancel = cancel;
    return {};
  }

  bool isDownloading(String id) => state.containsKey(id);

  Future<void> download(Track track) async {
    if (track.localPath != null || state.containsKey(track.id)) return;
    final token = CancelToken();
    _tokens[track.id] = token;
    state = {...state, track.id: (track: track, progress: 0.0)};
    NotificationService.instance
        .showDownloadProgress(track.id, track.title, 0);

    String? path;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/aurora');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      path = '${folder.path}/${track.id}.m4a';

      var lastNotif = 0;
      await _dio.download(
        '${AppConfig.apiBase}/stream?v=${track.id}',
        path,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final p = received / total;
          state = {...state, track.id: (track: track, progress: p)};
          final pct = (p * 100).round();
          if (pct >= lastNotif + 5 || pct == 100) {
            lastNotif = pct;
            NotificationService.instance
                .showDownloadProgress(track.id, track.title, pct);
          }
        },
      );

      final store = ref.read(localStoreProvider);
      await store.saveDownload(track.copyWith(localPath: path));
      try {
        final res = await _dio.get('${AppConfig.apiBase}/lyrics',
            queryParameters: {
              'title': track.title,
              'artist': track.artist,
              'duration': track.duration.inSeconds,
            });
        if (res.data is Map) {
          await store.saveLyrics(
              track.id, Map<String, dynamic>.from(res.data as Map));
        }
      } catch (_) {/* lyrics optional */}

      ref.invalidate(downloadsProvider);
      NotificationService.instance.showDownloadDone(track.id, track.title);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        NotificationService.instance.cancelDownloadNotif(track.id);
        if (path != null) _deleteQuiet(path);
      } else {
        NotificationService.instance.showDownloadError(track.id, track.title);
      }
    } catch (_) {
      NotificationService.instance.showDownloadError(track.id, track.title);
    } finally {
      _tokens.remove(track.id);
      state = {...state}..remove(track.id);
    }
  }

  void cancel(String id) {
    _tokens[id]?.cancel('cancelled');
    NotificationService.instance.cancelDownloadNotif(id);
    state = {...state}..remove(id);
  }

  void _deleteQuiet(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

final downloadControllerProvider =
    NotifierProvider<DownloadController, Map<String, DownloadJob>>(
        DownloadController.new);
