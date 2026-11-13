import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/datasources/yt_stream_resolver.dart';
import '../../domain/entities/track.dart';
import '../../core/downloads/music_folder.dart';
import 'connectivity_controller.dart';
import 'device_music_controller.dart';
import 'providers.dart';

typedef DownloadJob = ({Track track, double progress, bool paused});

/// Resumable downloads (HTTP Range) of a track's audio + lyrics into local
/// storage, with live progress / pause / resume / cancel via notification
/// actions and the Queue tab.
class DownloadController extends Notifier<Map<String, DownloadJob>> {
  final Dio _dio = Dio(BaseOptions(
    headers: AppConfig.apiSecretKey.isNotEmpty
        ? {'x-api-key': AppConfig.apiSecretKey}
        : null,
  ));
  final Map<String, CancelToken> _tokens = {};

  @override
  Map<String, DownloadJob> build() {
    NotificationService.instance
      ..onDownloadCancel = cancel
      ..onDownloadPause = pause
      ..onDownloadResume = resume;
    // If Wi-Fi-only is on and the radio drops, pause active transfers.
    ref.listen<AsyncValue<bool>>(wifiConnectivityProvider, (prev, next) {
      final onWifi = next.valueOrNull;
      if (onWifi == false && ref.read(wifiOnlyDownloadsProvider)) {
        for (final id in state.keys.toList()) {
          final job = state[id];
          if (job != null && !job.paused) pause(id);
        }
      }
    });
    return {};
  }

  bool isDownloading(String id) => state.containsKey(id);

  Future<bool> _wifiAllowed() async {
    if (!ref.read(wifiOnlyDownloadsProvider)) return true;
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }

  Future<String> _filePath(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/aurora');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return '${folder.path}/$id.m4a';
  }

  /// Downloads queued for the Most played list (see [LocalStore.saveDownload]).
  final Set<String> _autoIds = {};

  Future<void> download(Track track, {bool auto = false}) async {
    if (track.localPath != null || state.containsKey(track.id)) return;
    if (!await _wifiAllowed()) {
      NotificationService.instance.showDownloadError(
        track.id,
        track.title,
        headline: 'Wi‑Fi required',
      );
      return;
    }
    auto ? _autoIds.add(track.id) : _autoIds.remove(track.id);
    state = {...state, track.id: (track: track, progress: 0.0, paused: false)};
    await _run(track);
  }

  /// Recreate app-private files after reinstall. The resolver's persistent
  /// cache means this normally copies bytes already stored on the server and
  /// does not download the track from YouTube again.
  Future<void> restoreDownloads(List<Track> tracks) async {
    final store = ref.read(localStoreProvider);
    // Files already in Music/Aurora (e.g. after a reinstall) are linked, not
    // downloaded again.
    await linkMusicFolder(store);
    for (final track in tracks) {
      final existing = store.downloads().where((item) => item.id == track.id);
      if (existing.isNotEmpty) {
        final path = existing.first.localPath;
        if (path != null &&
            (isSharedMediaPath(path) || File(path).existsSync())) {
          continue;
        }
      }
      if (!state.containsKey(track.id)) {
        await download(track, auto: store.isAutoDownload(track.id));
      }
    }
  }

  Future<void> resume(String id) async {
    final job = state[id];
    if (job == null || !job.paused) return;
    if (!await _wifiAllowed()) {
      NotificationService.instance.showDownloadError(
        id,
        job.track.title,
        headline: 'Wi‑Fi required',
      );
      return;
    }
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
    _autoIds.remove(id);
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
      // Resolve the audio URL on-device (residential IP), then stream it.
      final src = await ref.read(musicRepositoryProvider).resolveStream(t);
      final resp = await _dio.getUri<ResponseBody>(
        src,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            ...ytStreamHeaders,
            if (existing > 0) 'Range': 'bytes=$existing-',
          },
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

      sink =
          file.openWrite(mode: existing > 0 ? FileMode.append : FileMode.write);
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
            NotificationService.instance
                .showDownloadProgress(t.id, t.title, pct);
          }
        }
      }
      await sink.close();
      sink = null;

      final store = ref.read(localStoreProvider);
      // App storage is wiped with the app; Music/Aurora survives a reinstall.
      // The private copy only stays if shared storage is not writable.
      var localPath = path;
      final shared = await saveToMusicFolder(path, t);
      if (shared != null) {
        _deleteQuiet(path);
        localPath = shared;
      }
      await store.saveDownload(t.copyWith(localPath: localPath),
          auto: _autoIds.remove(t.id));
      try {
        final r =
            await _dio.get('${AppConfig.apiBase}/lyrics', queryParameters: {
          'title': t.title,
          'artist': t.artist,
          'duration': t.duration.inSeconds,
        });
        if (r.data is Map) {
          final lyrics = Map<String, dynamic>.from(r.data as Map);
          if (lyrics['found'] == true && lyrics['matchVersion'] == 3) {
            await store.saveLyrics(t.id, lyrics);
          }
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

  /// Removes an offline copy: the file, its index entry, and (through the
  /// tombstone the store records) the same download on other devices.
  ///
  /// Shared Music/Aurora files: this install's go silently; one from a
  /// previous install needs Android's confirmation, which is shown only when
  /// [interactive] (a user tap). Returns false if the file stayed.
  Future<bool> deleteDownload(Track track, {bool interactive = true}) async {
    if (state.containsKey(track.id)) cancel(track.id);
    final store = ref.read(localStoreProvider);
    final path = track.localPath ??
        store.downloadPath(track.id) ??
        await _filePath(track.id);
    if (isSharedMediaPath(path)) {
      final bool gone;
      if (!await mediaExists(path)) {
        gone = true; // removed outside the app already
      } else if (interactive && await systemConfirmsDelete(path)) {
        // Android 11+: its own dialog is the only confirmation (the UI does
        // not ask first), for this install's files and a previous one's.
        gone = await deleteWithPrompt(path);
      } else {
        gone = await deleteOwnMedia([path]) > 0 ||
            (interactive &&
                path.startsWith('content://') &&
                await deleteWithPrompt(path));
      }
      // Background clean-up (Most played) never prompts, and a declined
      // Android dialog keeps the file: keep the download too, rather than
      // leave a file the app no longer lists.
      if (!gone) return false;
    } else {
      _deleteQuiet(path);
    }
    await store.removeDownload(track.id);
    ref.invalidate(downloadsProvider);
    return true;
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

/// Links the shared Music/Aurora folder to the downloads index: on start,
/// whenever audio access becomes granted (a reinstall's files are invisible
/// until then), and on demand from the Downloaded tab. Read once from the
/// app root.
class MusicFolderLinker extends Notifier<void> {
  bool _running = false;

  @override
  void build() {
    ref.listen(audioPermissionProvider, (_, next) {
      if (next.valueOrNull == true) unawaited(run());
    });
    Future<void>.delayed(const Duration(seconds: 2), run);
  }

  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      if (await linkMusicFolder(ref.read(localStoreProvider))) {
        ref.invalidate(downloadsProvider);
      }
    } catch (e) {
      debugPrint('[downloads] linking Music/Aurora failed: $e');
    } finally {
      _running = false;
    }
  }
}

final musicFolderLinkProvider =
    NotifierProvider<MusicFolderLinker, void>(MusicFolderLinker.new);
