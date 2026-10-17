import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/playlist.dart';
import '../../domain/entities/recent_playlist.dart';
import '../../domain/entities/track.dart';
import 'providers.dart';

/// Bumping the revision rebuilds many providers (some hit the network), so
/// it waits until the tapped track has had a chance to start loading. The
/// controller is read now because the calling widget may be gone by then.
Future<void> _bump(WidgetRef ref) async {
  final revision = ref.read(syncRevisionProvider.notifier);
  Future<void>.delayed(const Duration(seconds: 2), () => revision.state++);
}

/// Records a library playlist as recently played (Home 2×2).
Future<void> recordLibraryPlaylistPlay(
  WidgetRef ref,
  Playlist playlist,
) async {
  if (playlist.tracks.isEmpty) return;
  final art = playlist.coverUrl ?? '';
  await ref.read(localStoreProvider).pushRecentPlaylist(
        RecentPlaylist.library(
          libraryId: playlist.id,
          title: playlist.name,
          artworkUrl: art,
          tracks: playlist.tracks,
        ),
      );
  await _bump(ref);
}

/// Records a YouTube browse collection as recently played (Home 2×2).
Future<void> recordYoutubePlaylistPlay(
  WidgetRef ref, {
  required Track seed,
  required String title,
  required List<Track> tracks,
}) async {
  final url = seed.browseUrl;
  if (url == null || url.isEmpty || tracks.isEmpty) return;
  final art = seed.artworkUrl.isNotEmpty
      ? seed.artworkUrl
      : (tracks.first.artworkUrl);
  await ref.read(localStoreProvider).pushRecentPlaylist(
        RecentPlaylist.youtube(
          browseUrl: url,
          title: title,
          artworkUrl: art,
          tracks: tracks,
        ),
      );
  await _bump(ref);
}
