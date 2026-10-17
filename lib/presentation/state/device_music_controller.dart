import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/track.dart';
import 'favorites_controller.dart';
import 'player_controller.dart';
import 'playlist_controller.dart';
import 'providers.dart';

// Native MediaStore scan (Kotlin) — stable, off the UI thread. Replaces
// on_audio_query.querySongs which crashed with "Reply already submitted".
const _mediaCh = MethodChannel('aurora/media');

/// One device music folder with its tracks.
class MusicFolder {
  final String path;
  final List<Track> tracks;
  const MusicFolder(this.path, this.tracks);

  String get name {
    final parts = path.split('/')..removeWhere((s) => s.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  Duration get total => tracks.fold(Duration.zero, (s, t) => s + t.duration);
}

String _folderOf(String filePath) {
  final i = filePath.lastIndexOf('/');
  return i <= 0 ? filePath : filePath.substring(0, i);
}

Track _toTrack(Map<dynamic, dynamic> m) {
  final id = m['id'] as String;
  final artist = (m['artist'] as String?) ?? 'Unknown artist';
  return Track(
    id: id,
    title: (m['title'] as String?) ?? 'Unknown',
    artist: (artist == '<unknown>') ? 'Unknown artist' : artist,
    artworkUrl: '', // local art resolved via QueryArtworkWidget by id
    duration: Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0),
    accent: Track.accentFor(id),
    localPath: m['data'] as String?,
  );
}

/// Scans the device library (requests permission on first use).
/// Audio-library permission — CHECK ONLY (never auto-prompts, so the dialog
/// doesn't keep reappearing). The "Grant access" button calls [requestAudio].
final audioPermissionProvider = FutureProvider<bool>((ref) async {
  if (await Permission.audio.status.isGranted) return true;
  if (await Permission.storage.status.isGranted) return true;
  return false;
});

/// Actually prompts for the permission (called from the gate button).
Future<bool> requestAudioPermission() async {
  // Request both concurrently to avoid hanging on Android version edge-cases.
  final statuses = await [
    Permission.audio,
    Permission.storage,
  ].request();

  return statuses[Permission.audio]?.isGranted == true ||
      statuses[Permission.storage]?.isGranted == true;
}

// Dedupe to a single in-flight scan.
Future<List<Track>>? _inflight;

Future<List<Track>> _queryOnce() {
  return _inflight ??= () async {
    try {
      final res =
          await _mediaCh.invokeMethod<List<dynamic>>('querySongs') ?? const [];
      return res
          .map((e) => _toTrack(Map<dynamic, dynamic>.from(e as Map)))
          .toList(growable: false);
    } finally {
      _inflight = null;
    }
  }();
}

/// Returns all audio tracks; UI groups + filters by folder.
final deviceSongsProvider = FutureProvider<List<Track>>((ref) async {
  // Gate on the OS permission only (permission_handler). The plugin's own
  // permissionsStatus() is unreliable — it can report denied even after the
  // user grants, which caused an endless re-prompt loop.
  final granted = await ref.watch(audioPermissionProvider.future);
  if (!granted) throw const _PermissionDenied();
  return _queryOnce();
});

class _PermissionDenied implements Exception {
  const _PermissionDenied();
  @override
  String toString() => 'permission-denied';
}

/// Folders derived from the scan, honoring the hidden-folders setting.
final musicFoldersProvider = Provider<AsyncValue<List<MusicFolder>>>((ref) {
  final songs = ref.watch(deviceSongsProvider);
  return songs.whenData((tracks) {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      if (t.localPath == null) continue;
      map.putIfAbsent(_folderOf(t.localPath!), () => []).add(t);
    }
    final folders = map.entries.map((e) => MusicFolder(e.key, e.value)).toList()
      ..sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
    // Keep hidden folders in the list (shown toggled-off); filtering for
    // playback happens in visibleDeviceTracksProvider.
    return folders;
  });
});

/// Tracks from visible (non-hidden) folders only — used for "Play all".
final visibleDeviceTracksProvider = Provider<List<Track>>((ref) {
  final folders = ref.watch(musicFoldersProvider).valueOrNull ?? const [];
  final hidden = ref.watch(hiddenFoldersProvider);
  return [
    for (final f in folders)
      if (!hidden.contains(f.path)) ...f.tracks,
  ];
});

/// Persisted set of hidden folder paths.
class HiddenFoldersController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(syncRevisionProvider);
    return ref.watch(localStoreProvider).hiddenFolders();
  }

  Future<void> toggle(String path) async {
    final next = {...state};
    next.contains(path) ? next.remove(path) : next.add(path);
    await ref.read(localStoreProvider).setHiddenFolders(next);
    state = next;
  }

  bool isHidden(String path) => state.contains(path);
}

final hiddenFoldersProvider =
    NotifierProvider<HiddenFoldersController, Set<String>>(
        HiddenFoldersController.new);

/// Permanently deletes device songs (file + MediaStore row) after Android's
/// own confirmation dialog, then drops them from Liked Songs, playlists,
/// recents and stats so nothing points at a missing file. Returns false when
/// the user declined; throws [PlatformException] when Android refused.
///
/// Takes the [ProviderContainer] rather than a widget ref because the menu
/// that starts it closes while the system dialog is up.
Future<bool> deleteDeviceSongs(
    ProviderContainer ref, List<Track> tracks) async {
  if (tracks.isEmpty) return false;
  // Android 9 and older need WRITE_EXTERNAL_STORAGE; newer versions answer
  // this without a dialog and ask in the system delete prompt instead.
  try {
    await Permission.storage.request();
  } catch (_) {}
  final ok = await _mediaCh.invokeMethod<bool>(
        'deleteSongs',
        {'ids': [for (final t in tracks) t.id]},
      ) ??
      false;
  if (!ok) return false;

  final ids = {for (final t in tracks) t.id};
  final player = ref.read(playerControllerProvider.notifier);
  final playerState = ref.read(playerControllerProvider);
  if (ids.contains(playerState.current?.id)) {
    playerState.queue.length > 1 ? await player.next() : await player.close();
  }

  final favorites = ref.read(favoritesProvider.notifier);
  for (final t in ref.read(favoritesProvider)) {
    if (ids.contains(t.id)) await favorites.toggle(t);
  }
  final playlists = ref.read(playlistsProvider.notifier);
  for (final p in ref.read(playlistsProvider)) {
    for (final t in p.tracks) {
      if (ids.contains(t.id)) await playlists.removeTrack(p.id, t.id);
    }
  }
  final store = ref.read(localStoreProvider);
  for (final id in ids) {
    await store.forgetTrackHistory(id);
  }
  ref.invalidate(listeningStatsProvider);
  ref.invalidate(recentlyPlayedProvider);
  ref.invalidate(deviceSongsProvider);
  return true;
}
