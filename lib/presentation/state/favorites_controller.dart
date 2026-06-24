import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/track.dart';
import 'providers.dart';

/// Hive-backed "Liked Songs". State mirrors the favorites box.
class FavoritesController extends Notifier<List<Track>> {
  @override
  List<Track> build() => ref.watch(localStoreProvider).favorites();

  bool contains(String id) => state.any((t) => t.id == id);

  Future<void> toggle(Track track) async {
    await ref.read(localStoreProvider).toggleFavorite(track);
    state = ref.read(localStoreProvider).favorites();
  }
}

final favoritesProvider =
    NotifierProvider<FavoritesController, List<Track>>(FavoritesController.new);
