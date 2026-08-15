import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';

/// Thin Hive wrapper. Offline-first index for playlists, recents, downloads.
/// Stores plain JSON maps so no codegen/adapters are required.
class LocalStore {
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

  Future<void> savePlaylist(Playlist p) =>
      _playlists.put(p.id, p.toJson());

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
    final rows = _stats.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
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

  // --- Simple bool/string settings ---------------------------------------
  bool flag(String key, {bool fallback = false}) =>
      (_settings.get(key) as bool?) ?? fallback;

  Future<void> setFlag(String key, bool value) => _settings.put(key, value);

  int? number(String key) => (_settings.get(key) as num?)?.toInt();

  Future<void> setNumber(String key, int value) => _settings.put(key, value);
}
