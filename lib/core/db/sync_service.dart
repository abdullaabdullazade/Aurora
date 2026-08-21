import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../presentation/state/auth_controller.dart';
import '../../presentation/state/download_controller.dart';
import '../../presentation/state/providers.dart';
import '../config/app_config.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref);
  ref.listen<AsyncValue<User?>>(authStateProvider, (previous, current) {
    if (current.valueOrNull != null) {
      unawaited(service.syncAll());
    }
  }, fireImmediately: true);
  return service;
});

/// Offline-first sync between Hive and the private Aurora server.
///
/// The server authenticates every request with the current Firebase ID token;
/// the UID is derived from that verified token and is never trusted from a
/// client-provided query/body field.
class SyncService {
  SyncService(this._ref)
      : _dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBase,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 30),
          headers: AppConfig.apiSecretKey.isNotEmpty
              ? {'x-api-key': AppConfig.apiSecretKey}
              : null,
        )) {
    _changeSubscription =
        _ref.read(localStoreProvider).changes.listen((_) => _scheduleUpload());
    _ref.onDispose(() {
      _uploadDebounce?.cancel();
      _changeSubscription.cancel();
    });
  }

  final Ref _ref;
  final Dio _dio;
  late final StreamSubscription<void> _changeSubscription;
  Timer? _uploadDebounce;
  bool _syncing = false;

  Future<Options?> _authOptions() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) return null;
    return Options(headers: {'authorization': 'Bearer $token'});
  }

  Map<String, dynamic> _trackPayload(Track track) => {
        ...track.toJson(),
        // Device paths are meaningless after reinstall or on another phone.
        'localPath': null,
      };

  Map<String, dynamic> _playlistPayload(Playlist playlist) => {
        'id': playlist.id,
        'name': playlist.name,
        'tracks': playlist.tracks.map(_trackPayload).toList(),
      };

  Future<void> syncAll() async {
    if (_syncing) return;
    final options = await _authOptions();
    if (options == null) return;
    _syncing = true;
    try {
      final store = _ref.read(localStoreProvider);

      // Pull first so server tombstones prevent a playlist deleted on another
      // device from being resurrected by stale local state.
      final response = await _dio.get('/sync', options: options);
      final data = Map<String, dynamic>.from(response.data as Map);

      for (final id in (data['deletedPlaylists'] as List? ?? const [])) {
        await store.deletePlaylist(id as String);
      }
      for (final id in (data['deletedFavorites'] as List? ?? const [])) {
        await store.removeFavorite(id as String);
      }
      for (final raw in (data['playlists'] as List? ?? const [])) {
        await store.savePlaylist(
          Playlist.fromJson(Map<dynamic, dynamic>.from(raw as Map)),
        );
      }
      for (final raw in (data['favorites'] as List? ?? const [])) {
        await store.saveFavorite(
          Track.fromJson(Map<dynamic, dynamic>.from(raw as Map)),
        );
      }
      final remoteState = data['state'];
      final desiredDownloads = remoteState is Map
          ? await store.mergeSyncState(remoteState)
          : <Track>[];

      // Push the merged local snapshot. An empty store after reinstall does
      // not clear remote records; it only uploads items that actually exist.
      await _dio.put(
        '/sync',
        data: {
          'playlists': store.playlists().map(_playlistPayload).toList(),
          'favorites': store.favorites().map(_trackPayload).toList(),
          'state': store.syncState(),
        },
        options: options,
      );
      _notifyLocalChanged();
      if (desiredDownloads.isNotEmpty) {
        unawaited(_ref
            .read(downloadControllerProvider.notifier)
            .restoreDownloads(desiredDownloads));
      }
    } on DioException catch (error) {
      debugPrint('[sync] full sync failed: ${error.response?.statusCode} '
          '${error.message}');
    } catch (error) {
      debugPrint('[sync] full sync failed: $error');
    } finally {
      _syncing = false;
    }
  }

  Future<void> pushFavorite(Track track, bool isLiked) async {
    await _writeOne(
      kind: 'favorites',
      id: track.id,
      payload: isLiked ? _trackPayload(track) : null,
    );
  }

  Future<void> pushPlaylist(Playlist playlist) async {
    await _writeOne(
      kind: 'playlists',
      id: playlist.id,
      payload: _playlistPayload(playlist),
    );
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _writeOne(kind: 'playlists', id: playlistId, payload: null);
  }

  Future<void> _writeOne({
    required String kind,
    required String id,
    required Map<String, dynamic>? payload,
  }) async {
    final options = await _authOptions();
    if (options == null) return;
    try {
      final path = '/sync/$kind/$id';
      if (payload == null) {
        await _dio.delete(path, options: options);
      } else {
        await _dio.put(path, data: payload, options: options);
      }
    } on DioException catch (error) {
      debugPrint('[sync] $kind/$id failed: ${error.response?.statusCode} '
          '${error.message}');
    } catch (error) {
      debugPrint('[sync] $kind/$id failed: $error');
    }
  }

  void _scheduleUpload() {
    if (FirebaseAuth.instance.currentUser == null) return;
    _uploadDebounce?.cancel();
    _uploadDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(_pushSnapshot());
    });
  }

  Future<void> _pushSnapshot() async {
    if (_syncing) return;
    final options = await _authOptions();
    if (options == null) return;
    try {
      final store = _ref.read(localStoreProvider);
      await _dio.put(
        '/sync',
        data: {
          'playlists': store.playlists().map(_playlistPayload).toList(),
          'favorites': store.favorites().map(_trackPayload).toList(),
          'state': store.syncState(),
        },
        options: options,
      );
    } on DioException catch (error) {
      debugPrint('[sync] snapshot upload failed: '
          '${error.response?.statusCode} ${error.message}');
    } catch (error) {
      debugPrint('[sync] snapshot upload failed: $error');
    }
  }

  void _notifyLocalChanged() {
    final notifier = _ref.read(syncRevisionProvider.notifier);
    notifier.state++;
  }
}
