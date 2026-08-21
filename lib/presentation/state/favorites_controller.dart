import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/track.dart';
import '../../core/db/sync_service.dart';
import 'download_controller.dart';
import 'providers.dart';

/// Hive-backed "Liked Songs". State mirrors the favorites box.
class FavoritesController extends Notifier<List<Track>> {
  @override
  List<Track> build() {
    ref.watch(syncRevisionProvider);
    return ref.watch(localStoreProvider).favorites();
  }

  bool contains(String id) => state.any((t) => t.id == id);

  Future<void> toggle(Track track) async {
    final wasLiked = contains(track.id);
    await ref.read(localStoreProvider).toggleFavorite(track);
    state = ref.read(localStoreProvider).favorites();
    await ref.read(syncServiceProvider).pushFavorite(track, !wasLiked);
    if (!wasLiked) await _maybeDownload(track);
  }

  /// Liking a song with "Download liked songs" on should make it offline
  /// without a second trip through the menu.
  Future<void> _maybeDownload(Track track) async {
    if (!ref.read(autoDownloadFavoritesProvider)) return;
    if (track.localPath != null) return;
    final already =
        ref.read(localStoreProvider).downloads().any((t) => t.id == track.id);
    if (already) return;
    try {
      await ref.read(downloadControllerProvider.notifier).download(track);
    } catch (e) {
      debugPrint('[favorites] auto-download failed: $e');
    }
  }

  /// Fills in anything liked before the setting was switched on.
  Future<void> downloadAllLiked() async {
    for (final t in state) {
      await _maybeDownload(t);
    }
  }
}

final favoritesProvider =
    NotifierProvider<FavoritesController, List<Track>>(FavoritesController.new);
