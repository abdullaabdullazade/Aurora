import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/track.dart';
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

  Duration get total =>
      tracks.fold(Duration.zero, (s, t) => s + t.duration);
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
  return Permission.storage.status.isGranted;
});

/// Actually prompts for the permission (called from the gate button).
Future<bool> requestAudioPermission() async {
  var st = await Permission.audio.request(); // Android 13+ READ_MEDIA_AUDIO
  if (!st.isGranted) {
    final storage = await Permission.storage.request(); // <= Android 12
    if (storage.isGranted) st = storage;
  }
  return st.isGranted;
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
    final folders = map.entries
        .map((e) => MusicFolder(e.key, e.value))
        .toList()
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
  Set<String> build() => ref.watch(localStoreProvider).hiddenFolders();

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
