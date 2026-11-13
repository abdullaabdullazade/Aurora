import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/track.dart';
import '../db/local_store.dart';

/// Downloads live in the phone's shared Music/Aurora folder, not in app
/// storage, so they survive an uninstall; a reinstall finds them again by the
/// YouTube id kept in the file name.
const _media = MethodChannel('aurora/media');

/// Marks a path as a shared Music/Aurora file (content URI on Android 10+,
/// a public path on older versions) rather than an app-private one.
bool isSharedMediaPath(String path) =>
    path.startsWith('content://') || path.contains('/Music/Aurora/');

/// "Artist - Title [videoId].m4a"
String musicFileName(Track t) {
  String clean(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
  var base = '${clean(t.artist)} - ${clean(t.title)}';
  if (base.length > 120) base = base.substring(0, 120).trim();
  return '$base [${t.id}].m4a';
}

/// Reads a name written by [musicFileName] (MediaStore may add " (1)" on a
/// clash); null for any other file.
({String id, String artist, String title})? parseMusicFileName(String name) {
  final m = RegExp(r'^(.*) \[([A-Za-z0-9_-]{11})\](?: \(\d+\))?\.[A-Za-z0-9]+$')
      .firstMatch(name);
  if (m == null) return null;
  final base = m.group(1)!;
  final dash = base.indexOf(' - ');
  return (
    id: m.group(2)!,
    artist: dash > 0 ? base.substring(0, dash) : 'Unknown',
    title: dash > 0 ? base.substring(dash + 3) : base,
  );
}

/// Copies a finished download into Music/Aurora; returns where it now plays
/// from, or null if shared storage is not writable.
Future<String?> saveToMusicFolder(String path, Track track) async {
  try {
    return await _media.invokeMethod<String>(
        'saveToMusic', {'path': path, 'name': musicFileName(track)});
  } catch (e) {
    debugPrint('[downloads] saving to Music/Aurora failed: $e');
    return null;
  }
}

int? _sdk;

/// Android API level (0 when unknown).
Future<int> androidSdk() async {
  if (_sdk != null) return _sdk!;
  try {
    _sdk = await _media.invokeMethod<int>('sdkInt') ?? 0;
  } catch (_) {
    _sdk = 0;
  }
  return _sdk!;
}

/// On Android 11+ deleting a shared file always goes through Android's own
/// "Allow Aurora to delete?" dialog, so the app must not ask first as well.
Future<bool> systemConfirmsDelete(String path) async =>
    path.startsWith('content://') && await androidSdk() >= 30;

Future<bool> mediaExists(String path) async {
  try {
    return await _media.invokeMethod<bool>('mediaExists', {'uri': path}) ??
        true;
  } catch (_) {
    return true;
  }
}

/// Deletes shared files this install created, without a prompt. Returns how
/// many went; files of a previous install need [deleteWithPrompt].
Future<int> deleteOwnMedia(List<String> uris) async {
  if (uris.isEmpty) return 0;
  try {
    return await _media.invokeMethod<int>('deleteOwnMedia', {'uris': uris}) ??
        0;
  } catch (_) {
    return 0;
  }
}

/// Deletes a shared file through Android's own confirmation (needed for files
/// a previous install created). Returns false when the user declined.
Future<bool> deleteWithPrompt(String uri) async {
  final id = Uri.tryParse(uri)?.pathSegments.lastOrNull;
  if (id == null || int.tryParse(id) == null) return false;
  try {
    return await _media.invokeMethod<bool>('deleteSongs', {
          'ids': [id]
        }) ??
        false;
  } catch (_) {
    return false;
  }
}

/// Links Music/Aurora files to the downloads index: files from a previous
/// install come back as downloads (artwork from the id, nothing is fetched),
/// records whose file moved are repointed, and app-private downloads from
/// older versions are moved into the shared folder once. Returns whether
/// anything changed.
Future<bool> linkMusicFolder(LocalStore store) async {
  var changed = false;

  // 1. Older versions downloaded into app storage, which an uninstall wipes.
  for (final t in store.downloads()) {
    final path = t.localPath;
    if (path == null || isSharedMediaPath(path)) continue;
    if (!await File(path).exists()) continue;
    final shared = await saveToMusicFolder(path, t);
    if (shared == null) continue;
    await store.relinkDownload(t.id, shared);
    try {
      await File(path).delete();
    } catch (_) {}
    changed = true;
  }

  // 2. Files the index does not point at (reinstall, or synced records).
  List<dynamic> rows;
  try {
    rows = await _media.invokeMethod<List<dynamic>>('listAuroraMusic') ??
        const [];
  } catch (_) {
    return changed;
  }
  for (final raw in rows.whereType<Map>()) {
    final name = '${raw['name'] ?? ''}';
    final uri = '${raw['uri'] ?? ''}';
    final parsed = parseMusicFileName(name);
    if (parsed == null || uri.isEmpty) continue;
    if (store.isDownloadDeleted(parsed.id)) continue;
    if (store.downloadPath(parsed.id) == uri) continue;
    final existing = store.downloads().where((t) => t.id == parsed.id);
    if (existing.isNotEmpty) {
      await store.relinkDownload(parsed.id, uri);
    } else {
      final ms = (raw['duration'] as num?)?.toInt() ?? 0;
      await store.saveDownload(Track(
        id: parsed.id,
        title: parsed.title,
        artist: parsed.artist,
        artworkUrl: 'https://i.ytimg.com/vi/${parsed.id}/hqdefault.jpg',
        duration: Duration(milliseconds: ms),
        accent: Track.accentFor(parsed.id),
        localPath: uri,
      ));
    }
    changed = true;
  }
  return changed;
}
