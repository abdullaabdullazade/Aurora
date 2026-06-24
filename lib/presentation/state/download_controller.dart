import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/notifications/notification_service.dart';
import '../../domain/entities/track.dart';
import 'providers.dart';

typedef DownloadJob = ({Track track, double progress, bool paused});

/// Resumable downloads (HTTP Range) of a track's audio + lyrics into local
/// storage, with live progress / pause / resume / cancel via notification
/// actions and the Queue tab.
class DownloadController extends Notifier<Map<String, DownloadJob>> {
  final Dio _dio = Dio();
  final Map<String, CancelToken> _tokens = {};

  @override
  Map<String, DownloadJob> build() {
    NotificationService.instance
      ..onDownloadCancel = cancel
      ..onDownloadPause = pause
      ..onDownloadResume = resume;
    return {};
  }

  bool isDownloading(String id) => state.containsKey(id);

  Future<String> _filePath(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/aurora');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return '${folder.path}/$id.m4a';
  }

  Future<void> download(Track track) async {
    if (track.localPath != null || state.containsKey(track.id)) return;
    state = {...state, track.id: (track: track, progress: 0.0, paused: false)};
    await _run(track);
  }

  Future<void> resume(String id) async {
    final job = state[id];
    if (job == null || !job.paused) return;
    state = {
      ...state,
      id: (track: job.track, progress: job.progress, paused: false)
    };
    await _run(job.track);
  }

  void pause(String id) {
    final job = state[id];
    if (job == null) return;
    _tokens[id]?.cancel('pause');
    state = {
      ...state,
      id: (track: job.track, progress: job.progress, paused: true)
    };
    NotificationService.instance
        .showDownloadPaused(id, job.track.title, (job.progress * 100).round());
  }

  void cancel(String id) {
    final job = state[id];
    _tokens[id]?.cancel('cancel');
    NotificationService.instance.cancelDownloadNotif(id);
    _filePath(id).then(_deleteQuiet);
    state = {...state}..remove(id);
    if (job != null) {/* removed */}
  }

  Future<void> _run(Track t) async {
    final token = CancelToken();
    _tokens[t.id] = token;
    final path = await _filePath(t.id);
    final file = File(path);
    var existing = file.existsSync() ? await file.length() : 0;
    NotificationService.instance.showDownloadProgress(
        t.id, t.title, ((state[t.id]?.progress ?? 0) * 100).round());

    IOSink? sink;
    try {
      final resp = await _dio.get<ResponseBody>(
        '${AppConfig.apiBase}/stream?v=${t.id}',
        options: Options(
          responseType: ResponseType.stream,
          headers: existing > 0 ? {'Range': 'bytes=$existing-'} : null,
        ),
        cancelToken: token,
      );

      // Total size: from Content-Range (206) or existing + Content-Length.
      int total = 0;
      final cr = resp.headers.value('content-range');
      if (cr != null && cr.contains('/')) {
        total = int.tryParse(cr.split('/').last) ?? 0;
      } else {
        final cl =
            int.tryParse(resp.headers.value('content-length') ?? '0') ?? 0;
        total = existing + cl;
      }
      // Server ignored Range → restart from zero.
      if (resp.statusCode == 200 && existing > 0) {
        existing = 0;
        await file.writeAsBytes(const []);
      }

      sink = file.openWrite(
          mode: existing > 0 ? FileMode.append : FileMode.write);
      var received = existing;
      var lastPct = -1;
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final p = (received / total).clamp(0.0, 1.0);
          state = {...state, t.id: (track: t, progress: p, paused: false)};
          final pct = (p * 100).round();
          if (pct >= lastPct + 5 || pct == 100) {
            lastPct = pct;
            NotificationService.instance.showDownloadProgress(t.id, t.title, pct);
          }
        }
      }
      await sink.close();
      sink = null;

      final store = ref.read(localStoreProvider);
      await store.saveDownload(t.copyWith(localPath: path));
      try {
        final r = await _dio.get('${AppConfig.apiBase}/lyrics',
            queryParameters: {
              'title': t.title,
              'artist': t.artist,
              'duration': t.duration.inSeconds,
            });
        if (r.data is Map) {
          await store.saveLyrics(t.id, Map<String, dynamic>.from(r.data as Map));
        }
      } catch (_) {}

      ref.invalidate(downloadsProvider);
      NotificationService.instance.showDownloadDone(t.id, t.title);
      _tokens.remove(t.id);
      state = {...state}..remove(t.id);
    } on DioException catch (e) {
      await sink?.close();
      _tokens.remove(t.id);
      if (CancelToken.isCancel(e)) {
        // 'pause' keeps the partial file + paused state; 'cancel' already
        // cleaned up. Nothing else to do.
      } else {
        NotificationService.instance.showDownloadError(t.id, t.title);
        state = {...state}..remove(t.id);
      }
    } catch (_) {
      await sink?.close();
      _tokens.remove(t.id);
      NotificationService.instance.showDownloadError(t.id, t.title);
      state = {...state}..remove(t.id);
    }
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
