import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/track.dart';
import 'providers.dart';

final _audioQuery = OnAudioQuery();

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

Track _toTrack(SongModel s) => Track(
      id: s.id.toString(),
      title: s.title,
      artist: (s.artist == null || s.artist == '<unknown>')
          ? 'Unknown artist'
          : s.artist!,
      artworkUrl: '', // local art resolved via QueryArtworkWidget by id
      duration: Duration(milliseconds: s.duration ?? 0),
      accent: Track.accentFor(s.id.toString()),
      localPath: s.data,
    );

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

// Guards against concurrent querySongs calls — on_audio_query crashes with
// "Reply already submitted" if its query runs twice at once (e.g. a rebuild
// during the permission flow). Dedupe to a single in-flight query.
Future<List<Track>>? _inflight;

Future<List<Track>> _queryOnce() {
  return _inflight ??= () async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      return songs
          .where((s) => s.isMusic == true && (s.duration ?? 0) > 0)
          .map(_toTrack)
          .toList(growable: false);
    } finally {
      _inflight = null;
    }
  }();
}

/// Returns all audio tracks; UI groups + filters by folder.
final deviceSongsProvider = FutureProvider<List<Track>>((ref) async {
  final granted = await ref.watch(audioPermissionProvider.future);
  if (!granted) throw const _PermissionDenied();
  // Double-gate: on_audio_query crashes ("Reply already submitted") if its
  // query runs while the plugin itself reports no library access. Only query
  // when the plugin confirms access.
  if (!await _audioQuery.permissionsStatus()) throw const _PermissionDenied();
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
