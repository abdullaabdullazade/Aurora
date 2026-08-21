import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../presentation/state/auth_controller.dart';
import '../../presentation/state/providers.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref);
  ref.listen<AsyncValue<User?>>(authStateProvider, (previous, current) {
    if (current.value != null) {
      service.syncDown(current.value!.uid);
    }
  });
  return service;
});

class SyncService {
  final Ref _ref;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  SyncService(this._ref);

  Future<void> syncDown(String uid) async {
    final store = _ref.read(localStoreProvider);
    final userDoc = _db.collection('users').doc(uid);

    // 1. Sync Favorites
    final favSnapshot = await userDoc.collection('favorites').get();
    for (var doc in favSnapshot.docs) {
      final track = Track.fromJson(doc.data());
      if (!store.isFavorite(track.id)) {
        await store.toggleFavorite(track);
      }
    }

    // 2. Sync Playlists
    final plSnapshot = await userDoc.collection('playlists').get();
    for (var doc in plSnapshot.docs) {
      final playlist = Playlist.fromJson(doc.data());
      await store.savePlaylist(playlist);
    }
  }

  Future<void> pushFavorite(Track track, bool isLiked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final docRef = _db
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .doc(track.id);
        
    if (isLiked) {
      await docRef.set(track.toJson());
    } else {
      await docRef.delete();
    }
  }

  Future<void> pushPlaylist(Playlist playlist) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('playlists')
        .doc(playlist.id)
        .set(playlist.toJson());
  }

  Future<void> deletePlaylist(String playlistId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('playlists')
        .doc(playlistId)
        .delete();
  }
}
