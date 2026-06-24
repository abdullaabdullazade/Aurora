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
  static const _recentsKey = 'list';
  static const _maxRecents = 30;

  late final Box<dynamic> _playlists;
  late final Box<dynamic> _recents;
  late final Box<dynamic> _downloads;
  late final Box<dynamic> _favorites;
  late final Box<dynamic> _settings;

  Future<void> init() async {
    await Hive.initFlutter();
    _playlists = await Hive.openBox(_playlistsBox);
    _recents = await Hive.openBox(_recentsBox);
    _downloads = await Hive.openBox(_downloadsBox);
    _favorites = await Hive.openBox(_favoritesBox);
    _settings = await Hive.openBox(_settingsBox);
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

  // --- Downloads ---------------------------------------------------------
  List<Track> downloads() => _downloads.values
      .map((e) => Track.fromJson(Map<dynamic, dynamic>.from(e as Map)))
      .toList();

  Future<void> saveDownload(Track t) => _downloads.put(t.id, t.toJson());
}
