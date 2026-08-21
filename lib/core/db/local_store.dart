import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';

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
  static const _maxRecents = 30;
  static const _searchHistoryKey = 'search_history';
  static const _maxSearchHistory = 12;

  late final Box<dynamic> _playlists;
  late final Box<dynamic> _recents;
  late final Box<dynamic> _downloads;
  late final Box<dynamic> _favorites;
  late final Box<dynamic> _settings;
  late final Box<dynamic> _lyrics;
  late final Box<dynamic> _stats;

  Future<void> init() async {
    await Hive.initFlutter();
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

  Future<void> removeDownload(String id) async {
    await _downloads.delete(id);
    await _lyrics.delete(id);
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

  // --- Downloads ---------------------------------------------------------
  List<Track> downloads() => _downloads.values
      .map((e) => Track.fromJson(Map<dynamic, dynamic>.from(e as Map)))
      .toList();

  Future<void> saveDownload(Track t) => _downloads.put(t.id, t.toJson());

  // --- Account sync snapshot --------------------------------------------
  Map<String, dynamic> syncState() => {
        'version': 1,
        'recents': recents().map(_portableTrack).toList(),
        'downloads': downloads().map(_portableTrack).toList(),
        'lyrics': {
          for (final entry in _lyrics.toMap().entries)
            entry.key.toString(): _jsonValue(entry.value),
        },
        'stats': stats()
            .map((row) => _jsonValue({...row, 'localPath': null}))
            .toList(),
        'settings': {
          for (final entry in _settings.toMap().entries)
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

    final desiredDownloads = ((state['downloads'] as List?) ?? const [])
        .whereType<Map>()
        .map(Track.fromJson)
        .toList();
    for (final track in desiredDownloads) {
      if (!_downloads.containsKey(track.id)) {
        await _downloads.put(track.id, _portableTrack(track));
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
