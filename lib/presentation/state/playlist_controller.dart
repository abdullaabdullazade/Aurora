import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/local_store.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import 'providers.dart';

/// Hive-backed playlist CRUD. State is the in-memory mirror of the box.
class PlaylistController extends Notifier<List<Playlist>> {
  @override
  List<Playlist> build() => ref.watch(localStoreProvider).playlists();

  // ids are derived from track count + name hash to stay deterministic
  // (Date.now/random are avoided per environment constraints).
  String _newId(String name) =>
      'pl_${name.hashCode.toUnsigned(32).toRadixString(16)}_${state.length}';

  Future<Playlist> create(String name) async {
    final p = Playlist(id: _newId(name), name: name.trim());
    await ref.read(localStoreProvider).savePlaylist(p);
    state = [...state, p];
    return p;
  }

  Future<void> rename(String id, String name) async {
    await _update(id, (p) => p.copyWith(name: name.trim()));
  }

  Future<void> addTrack(String id, Track track) async {
    await _update(id, (p) {
      if (p.tracks.any((t) => t.id == track.id)) return p; // no dupes
      return p.copyWith(tracks: [...p.tracks, track]);
    });
  }

  Future<void> removeTrack(String id, String trackId) async {
    await _update(
        id, (p) => p.copyWith(tracks: p.tracks.where((t) => t.id != trackId).toList()));
  }

  Future<void> delete(String id) async {
    await ref.read(localStoreProvider).deletePlaylist(id);
    state = state.where((p) => p.id != id).toList();
  }

  Future<void> _update(String id, Playlist Function(Playlist) fn) async {
    final store = ref.read(localStoreProvider);
    state = [
      for (final p in state)
        if (p.id == id) await _persist(store, fn(p)) else p,
    ];
  }

  Future<Playlist> _persist(LocalStore store, Playlist p) async {
    await store.savePlaylist(p);
    return p;
  }
}

final playlistsProvider =
    NotifierProvider<PlaylistController, List<Playlist>>(
        PlaylistController.new);
