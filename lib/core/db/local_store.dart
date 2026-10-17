import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/recent_playlist.dart';
import '../../domain/entities/track.dart';

/// Last queue, track index, and scrub position for resume-on-launch.
@immutable
class PlaybackSession {
  const PlaybackSession({
    required this.queue,
    required this.index,
    required this.position,
    required this.savedAt,
  });

  final List<Track> queue;
  final int index;
  final Duration position;
  final DateTime savedAt;
}

/// Thin Hive wrapper. Offline-first index for playlists, recents, downloads.
/// Stores plain JSON maps so no codegen/adapters are required.
class LocalStore {
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  static const _playlistsBox = 'playlists';
  static const _recentsBox = 'recents';
  static const _downloadsBox = 'downloads';
  static const _favoritesBox = 'favorites';
  static const _settingsBox = 'settings';
  static const _lyricsBox = 'lyrics';
  static const _statsBox = 'stats';
  static const _recentsKey = 'list';
  static const _recentPlaylistsKey = 'playlists';
  static const _maxRecents = 30;
  static const _maxRecentPlaylists = 4;
  static const _searchHistoryKey = 'search_history';
  static const _maxSearchHistory = 12;
  static const _playbackSessionKey = 'playback_session';
  static const _playbackSessionMaxAge = Duration(days: 30);
  static const _downloadTombstonesKey = 'download_tombstones';
  static const _tombstoneMaxAge = Duration(days: 90);

  late final Box<dynamic> _playlists;
  late final Box<dynamic> _recents;
  late final Box<dynamic> _downloads;
  late final Box<dynamic> _favorites;
  late final Box<dynamic> _settings;
  late final Box<dynamic> _lyrics;
  late final Box<dynamic> _stats;

  /// [hivePath] is for tests, which have no Flutter documents directory.
  Future<void> init({@visibleForTesting String? hivePath}) async {
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }
    _playlists = await Hive.openBox(_playlistsBox);
    _recents = await Hive.openBox(_recentsBox);
    _downloads = await Hive.openBox(_downloadsBox);
    _favorites = await Hive.openBox(_favoritesBox);
    _settings = await Hive.openBox(_settingsBox);
    _lyrics = await Hive.openBox(_lyricsBox);
    _stats = await Hive.openBox(_statsBox);
    for (final box in [
      _playlists,
      _recents,
      _downloads,
      _favorites,
      _settings,
      _lyrics,
      _stats,
    ]) {
      box.watch().listen((_) => _changes.add(null));
    }
  }

  // --- Offline lyrics (saved alongside downloads) ------------------------
  Future<void> saveLyrics(String id, Map<String, dynamic> json) =>
      _lyrics.put(id, json);

  Map<dynamic, dynamic>? lyrics(String id) =>
      _lyrics.get(id) as Map<dynamic, dynamic>?;

  /// Drops a download and records when, so account sync removes it on the
  /// user's other devices instead of restoring it from their snapshot.
  Future<void> removeDownload(String id) async {
    await _downloads.delete(id);
    await _lyrics.delete(id);
    final tombstones = _downloadTombstones()
      ..[id] = DateTime.now().millisecondsSinceEpoch;
    await _recents.put(_downloadTombstonesKey, tombstones);
  }

  /// Deleted download id -> deletion time (ms since epoch).
  Map<String, int> _downloadTombstones() {
    final raw = _recents.get(_downloadTombstonesKey);
    if (raw is! Map) return {};
    final cutoff = DateTime.now()
        .subtract(_tombstoneMaxAge)
        .millisecondsSinceEpoch;
    return {
      for (final entry in raw.entries)
        if (entry.value is num && (entry.value as num).toInt() > cutoff)
          entry.key.toString(): (entry.value as num).toInt(),
    };
  }

  /// Deletes an audio file only if DownloadController wrote it (app-private
  /// `aurora/` folder) — never anything else on the device.
  Future<void> _deleteOwnFile(String? path) async {
    if (path == null) return;
    try {
      final ownDir =
          '${(await getApplicationDocumentsDirectory()).path}/aurora/';
      if (!path.startsWith(ownDir)) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[store] could not delete download $path: $e');
    }
  }

  // --- Favorites ---------------------------------------------------------
  List<Track> favorites() => _favorites.values
      .map((e) => Track.fromJson(Map<dynamic, dynamic>.from(e as Map)))
      .toList();

  bool isFavorite(String id) => _favorites.containsKey(id);

  Future<void> saveFavorite(Track track) =>
      _favorites.put(track.id, track.toJson());

  Future<void> removeFavorite(String id) => _favorites.delete(id);

  Future<void> toggleFavorite(Track t) async {
    if (_favorites.containsKey(t.id)) {
      await _favorites.delete(t.id);
    } else {
      await _favorites.put(t.id, t.toJson());
    }
  }

  // --- Hidden device folders --------------------------------------------
  static const _hiddenFoldersKey = 'hidden_folders';

  Set<String> hiddenFolders() {
    final raw = (_settings.get(_hiddenFoldersKey) as List?) ?? const [];
    return raw.map((e) => e as String).toSet();
  }

  Future<void> setHiddenFolders(Set<String> folders) =>
      _settings.put(_hiddenFoldersKey, folders.toList());

  // --- Theme mode --------------------------------------------------------
  /// 'dark' | 'light' | 'system' (defaults to dark — the app's native look).
  String themeMode() => (_settings.get('theme_mode') as String?) ?? 'dark';
  Future<void> setThemeMode(String mode) => _settings.put('theme_mode', mode);

  // --- Playlists ---------------------------------------------------------
  List<Playlist> playlists() => _playlists.values
      .map((e) => Playlist.fromJson(Map<dynamic, dynamic>.from(e as Map)))
      .toList();

  Future<void> savePlaylist(Playlist p) => _playlists.put(p.id, p.toJson());

  Future<void> deletePlaylist(String id) => _playlists.delete(id);

  // --- Recents -----------------------------------------------------------
  List<Track> recents() {
    final raw = (_recents.get(_recentsKey) as List?) ?? const [];
    return raw
        .map((e) => Track.fromJson(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> pushRecent(Track t) async {
    final list = recents()..removeWhere((e) => e.id == t.id);
    list.insert(0, t);
    final trimmed = list.take(_maxRecents).map((e) => e.toJson()).toList();
    await _recents.put(_recentsKey, trimmed);
  }

  // --- Recent playlists (Home 2×2 quick access) -------------------------
  List<RecentPlaylist> recentPlaylists() {
    final raw = (_recents.get(_recentPlaylistsKey) as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => RecentPlaylist.fromJson(Map<dynamic, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<void> pushRecentPlaylist(RecentPlaylist entry) async {
    final list = recentPlaylists().toList()
      ..removeWhere((e) => e.id == entry.id);
    list.insert(0, entry);
    final trimmed = list
        .take(_maxRecentPlaylists)
        .map((e) => e.toJson())
        .toList(growable: false);
    await _recents.put(_recentPlaylistsKey, trimmed);
  }

  // --- Search history ----------------------------------------------------
  List<String> searchHistory() =>
      ((_settings.get(_searchHistoryKey) as List?) ?? const [])
          .map((e) => e as String)
          .toList();

  Future<void> pushSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final list = searchHistory()
      ..removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    await _settings.put(
        _searchHistoryKey, list.take(_maxSearchHistory).toList());
  }

  Future<void> removeSearch(String query) async {
    final list = searchHistory()..remove(query);
    await _settings.put(_searchHistoryKey, list);
  }

  Future<void> clearSearchHistory() => _settings.delete(_searchHistoryKey);

  // --- Playback session (device-local, not synced) -----------------------
  PlaybackSession? playbackSession() {
    final raw = _settings.get(_playbackSessionKey);
    if (raw is! Map) return null;
    final map = Map<dynamic, dynamic>.from(raw);
    final queueRaw = map['queue'];
    if (queueRaw is! List || queueRaw.isEmpty) return null;
    final queue = queueRaw
        .whereType<Map>()
        .map(Track.fromJson)
        .toList(growable: false);
    if (queue.isEmpty) return null;
    final index = (map['index'] as num?)?.toInt() ?? 0;
    if (index < 0 || index >= queue.length) return null;
    final savedAtSec = (map['savedAt'] as num?)?.toInt();
    if (savedAtSec == null) return null;
    final savedAt =
        DateTime.fromMillisecondsSinceEpoch(savedAtSec * 1000, isUtc: true);
    if (DateTime.now().toUtc().difference(savedAt) > _playbackSessionMaxAge) {
      return null;
    }
    return PlaybackSession(
      queue: queue,
      index: index,
      position: Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
      savedAt: savedAt,
    );
  }

  Future<void> savePlaybackSession({
    required List<Track> queue,
    required int index,
    required Duration position,
  }) async {
    if (queue.isEmpty) return;
    final safeIndex = index.clamp(0, queue.length - 1);
    final track = queue[safeIndex];
    var positionMs = position.inMilliseconds;
    final totalMs = track.duration.inMilliseconds;
    if (totalMs > 0 && positionMs > totalMs * 0.95) {
      positionMs = 0;
    }
    await _settings.put(_playbackSessionKey, {
      'version': 1,
      // The session never leaves this device, so local paths stay valid.
      'queue': queue.map((t) => t.toJson()).toList(),
      'index': safeIndex,
      'positionMs': positionMs,
      'savedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  Future<void> clearPlaybackSession() =>
      _settings.delete(_playbackSessionKey);

  // --- Listening stats ---------------------------------------------------
  /// One row per track: how many times it started and how long it was heard.
  /// Recents are capped at 30 and reordered, so they cannot answer "what did
  /// I actually play this year" — this box is the durable record.
  Map<String, dynamic> _statRow(String id) {
    final raw = _stats.get(id);
    return raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(raw as Map);
  }

  Future<void> bumpPlay(Track t) async {
    final row = _statRow(t.id);
    // t.toJson() owns 'seconds' (the track's duration) — listening time lives
    // under its own key so the row stays a valid Track.fromJson input.
    await _stats.put(t.id, {
      ...t.toJson(),
      'count': ((row['count'] as num?)?.toInt() ?? 0) + 1,
      'seconds_played': (row['seconds_played'] as num?)?.toInt() ?? 0,
      'last': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> addListenTime(String id, int seconds) async {
    if (seconds <= 0) return;
    final row = _statRow(id);
    if (row.isEmpty) return;
    row['seconds_played'] =
        ((row['seconds_played'] as num?)?.toInt() ?? 0) + seconds;
    await _stats.put(id, row);
  }

  /// Raw stat rows, newest listen first.
  List<Map<String, dynamic>> stats() {
    final rows =
        _stats.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    rows.sort((a, b) =>
        ((b['last'] as num?) ?? 0).compareTo((a['last'] as num?) ?? 0));
    return rows;
  }

  Future<void> clearStats() => _stats.clear();

  /// Forgets a track everywhere history is kept (used when its file is gone).
  Future<void> forgetTrackHistory(String id) async {
    await _stats.delete(id);
    final raw = (_recents.get(_recentsKey) as List?) ?? const [];
    await _recents.put(_recentsKey, [
      for (final e in raw)
        if (!(e is Map && e['id'] == id)) e,
    ]);
  }

  /// Wipes per-account data when switching users or signing out.
  /// Device prefs (theme, crossfade, hidden folders) are kept. Downloaded
  /// audio files are deleted too: once the index is gone nothing references
  /// them, and the next account restores its own downloads on sign-in.
  Future<void> clearAccountData() async {
    for (final track in downloads()) {
      await _deleteOwnFile(track.localPath);
    }
    await Future.wait([
      clearPlaybackSession(),
      _playlists.clear(),
      _favorites.clear(),
      _recents.clear(),
      _stats.clear(),
      _downloads.clear(),
      _lyrics.clear(),
      clearSearchHistory(),
    ]);
  }

  String? lastAccountUid() => _settings.get('last_account_uid') as String?;

  Future<void> setLastAccountUid(String? uid) async {
    if (uid == null || uid.isEmpty) {
      await _settings.delete('last_account_uid');
    } else {
      await _settings.put('last_account_uid', uid);
    }
  }

  // --- Downloads ---------------------------------------------------------
  List<Track> downloads() => _downloads.values
      .map((e) => Track.fromJson(Map<dynamic, dynamic>.from(e as Map)))
      .toList();

  /// [auto] marks downloads made for the Most played list, which are removed
  /// again once the track drops out of it.
  Future<void> saveDownload(Track t, {bool auto = false}) async {
    await _downloads.put(t.id, {
      ...t.toJson(),
      'downloadedAt': DateTime.now().millisecondsSinceEpoch,
      'auto': auto,
    });
    // Downloading again overrides an earlier deletion.
    final tombstones = _downloadTombstones();
    if (tombstones.remove(t.id) != null) {
      await _recents.put(_downloadTombstonesKey, tombstones);
    }
  }

  /// File of a finished download, if this track has one.
  String? downloadPath(String id) {
    final raw = _downloads.get(id);
    return raw is Map ? raw['localPath'] as String? : null;
  }

  bool isAutoDownload(String id) {
    final raw = _downloads.get(id);
    return raw is Map && raw['auto'] == true;
  }

  int _downloadedAt(String id) {
    final raw = _downloads.get(id);
    return raw is Map ? (raw['downloadedAt'] as num?)?.toInt() ?? 0 : 0;
  }

  // --- Account sync snapshot --------------------------------------------
  Map<String, dynamic> syncState() => {
        'version': 1,
        'recents': recents().map(_portableTrack).toList(),
        'downloads': [
          for (final t in downloads())
            {
              ..._portableTrack(t),
              'downloadedAt': _downloadedAt(t.id),
              'auto': isAutoDownload(t.id),
            },
        ],
        'deletedDownloads': _downloadTombstones(),
        'lyrics': {
          for (final entry in _lyrics.toMap().entries)
            entry.key.toString(): _jsonValue(entry.value),
        },
        'stats': stats()
            .map((row) => _jsonValue({...row, 'localPath': null}))
            .toList(),
        'settings': {
          for (final entry in _settings.toMap().entries)
            if (entry.key.toString() != _playbackSessionKey)
              entry.key.toString(): _jsonValue(entry.value),
        },
      };

  /// Merge account data restored from the server. Returns the desired offline
  /// tracks so DownloadController can recreate missing files from server cache.
  Future<List<Track>> mergeSyncState(Map<dynamic, dynamic> state) async {
    final remoteRecents = ((state['recents'] as List?) ?? const [])
        .whereType<Map>()
        .map(Track.fromJson)
        .toList();
    final mergedRecents = <Track>[];
    final recentIds = <String>{};
    for (final track in [...remoteRecents, ...recents()]) {
      if (recentIds.add(track.id)) mergedRecents.add(track);
    }
    await _recents.put(
      _recentsKey,
      mergedRecents.take(_maxRecents).map(_portableTrack).toList(),
    );

    // Newest event per track wins: a deletion on one device removes the
    // download everywhere, and downloading again later brings it back.
    final tombstones = _downloadTombstones();
    final remoteTombstones = state['deletedDownloads'];
    if (remoteTombstones is Map) {
      for (final entry in remoteTombstones.entries) {
        final at = entry.value;
        if (at is! num) continue;
        final id = entry.key.toString();
        if (at.toInt() > (tombstones[id] ?? 0)) tombstones[id] = at.toInt();
      }
    }
    for (final entry in tombstones.entries) {
      if (!_downloads.containsKey(entry.key)) continue;
      if (_downloadedAt(entry.key) >= entry.value) continue;
      final raw = _downloads.get(entry.key);
      await _deleteOwnFile(raw is Map ? raw['localPath'] as String? : null);
      await _downloads.delete(entry.key);
      await _lyrics.delete(entry.key);
    }
    await _recents.put(_downloadTombstonesKey, tombstones);

    final desiredDownloads = <Track>[];
    for (final raw
        in ((state['downloads'] as List?) ?? const []).whereType<Map>()) {
      final track = Track.fromJson(raw);
      final at = (raw['downloadedAt'] as num?)?.toInt() ?? 0;
      final deletedAt = tombstones[track.id];
      if (deletedAt != null && deletedAt >= at) continue;
      desiredDownloads.add(track);
      if (!_downloads.containsKey(track.id)) {
        await _downloads.put(track.id, {
          ..._portableTrack(track),
          'downloadedAt': at,
          'auto': raw['auto'] == true,
        });
      }
    }

    final remoteLyrics = state['lyrics'];
    if (remoteLyrics is Map) {
      for (final entry in remoteLyrics.entries) {
        if (!_lyrics.containsKey(entry.key.toString()) && entry.value is Map) {
          await _lyrics.put(
            entry.key.toString(),
            Map<dynamic, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    for (final raw in (state['stats'] as List? ?? const []).whereType<Map>()) {
      final remote = Map<String, dynamic>.from(raw);
      final id = remote['id'];
      if (id is! String) continue;
      final local = _statRow(id);
      final remoteLast = (remote['last'] as num?)?.toInt() ?? 0;
      final localLast = (local['last'] as num?)?.toInt() ?? 0;
      if (local.isEmpty || remoteLast > localLast) {
        await _stats.put(id, remote);
      }
    }

    final remoteSettings = state['settings'];
    if (remoteSettings is Map) {
      for (final entry in remoteSettings.entries) {
        final key = entry.key.toString();
        if (key == _playbackSessionKey) continue;
        if (!_settings.containsKey(key)) {
          await _settings.put(key, entry.value);
        }
      }
    }
    return desiredDownloads;
  }

  Map<String, dynamic> _portableTrack(Track track) => {
        ...track.toJson(),
        // App-private paths cannot survive uninstall or move across devices.
        'localPath': null,
      };

  dynamic _jsonValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) return value.map(_jsonValue).toList();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonValue(entry.value),
      };
    }
    return value.toString();
  }

  // --- Simple bool/string settings ---------------------------------------
  bool flag(String key, {bool fallback = false}) =>
      (_settings.get(key) as bool?) ?? fallback;

  Future<void> setFlag(String key, bool value) => _settings.put(key, value);

  int? number(String key) => (_settings.get(key) as num?)?.toInt();

  Future<void> setNumber(String key, int value) => _settings.put(key, value);
}
