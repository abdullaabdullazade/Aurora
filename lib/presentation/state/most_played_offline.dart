import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/track.dart';
import 'connectivity_controller.dart';
import 'download_controller.dart';
import 'favorites_controller.dart';
import 'player_controller.dart';
import 'providers.dart';

/// Keeps [mostPlayedProvider] downloaded while [offlineMostPlayedProvider] is
/// on, like Spotify's auto-downloaded "On Repeat": new entries are fetched
/// (Wi-Fi only, it runs in the background) and tracks that drop out of the
/// list are removed again. Only downloads it made itself are ever removed.
/// Read once from the app root so it lives as long as the app.
final mostPlayedOfflineSyncProvider = Provider<void>((ref) {
  Timer? debounce;
  var running = false;
  var rerun = false;

  Future<void> run() async {
    if (running) {
      rerun = true;
      return;
    }
    running = true;
    try {
      do {
        rerun = false;
        await _reconcile(ref);
      } while (rerun);
    } catch (e, st) {
      debugPrint('[most-played] offline sync failed: $e\n$st');
    } finally {
      running = false;
    }
  }

  // Stats change on every play; batch them instead of reconciling each time.
  void schedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 5), () => unawaited(run()));
  }

  ref.listen(mostPlayedProvider, (_, __) => schedule());
  ref.listen(offlineMostPlayedProvider, (_, __) => schedule());
  ref.listen(isWifiProvider, (_, __) => schedule());
  ref.onDispose(() => debounce?.cancel());
  schedule();
});

/// Device (MediaStore) rows have short numeric ids and are already local.
bool _isDeviceTrack(Track t) => t.id.length < 11 && int.tryParse(t.id) != null;

Future<void> _reconcile(Ref ref) async {
  final store = ref.read(localStoreProvider);
  final downloader = ref.read(downloadControllerProvider.notifier);
  final enabled = ref.read(offlineMostPlayedProvider);
  final wanted = <String, Track>{
    if (enabled)
      for (final s in ref.read(mostPlayedProvider))
        if (!_isDeviceTrack(s.track)) s.track.id: s.track,
  };

  // A liked song stays when "Download liked songs" is on.
  final keepLiked = ref.read(autoDownloadFavoritesProvider);
  final liked = {for (final t in ref.read(favoritesProvider)) t.id};
  final playingId = ref.read(playerControllerProvider).current?.id;
  for (final t in store.downloads()) {
    if (!store.isAutoDownload(t.id) || wanted.containsKey(t.id)) continue;
    if (keepLiked && liked.contains(t.id)) continue;
    // Pulling the file from under the player would cut the song off; the
    // next pass removes it.
    if (t.id == playingId) continue;
    await downloader.deleteDownload(t);
  }
  if (wanted.isEmpty) return;

  final network = await Connectivity().checkConnectivity();
  if (!network.contains(ConnectivityResult.wifi)) return;

  final downloaded = {for (final t in store.downloads()) t.id};
  for (final t in wanted.values) {
    if (downloaded.contains(t.id) || downloader.isDownloading(t.id)) continue;
    if (!ref.read(offlineMostPlayedProvider)) return; // turned off meanwhile
    // Stats rows can carry a stale path; download() skips tracks that have one.
    final clean = Track.fromJson({...t.toJson(), 'localPath': null});
    await downloader.download(clean, auto: true);
  }
}
