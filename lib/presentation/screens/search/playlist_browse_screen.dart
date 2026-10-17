import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/track.dart';
import '../../state/player_controller.dart';
import '../../state/playlist_controller.dart';
import '../../state/providers.dart';
import '../../state/recent_playlists.dart';
import '../../widgets/artwork.dart';
import '../../widgets/track_tile.dart';
import '../library/add_to_playlist_sheet.dart';

/// Expands a YouTube playlist / album / podcast search hit into playable tracks.
class PlaylistBrowseScreen extends ConsumerWidget {
  final Track seed;
  const PlaylistBrowseScreen({super.key, required this.seed});

  String get _heading => switch (seed.kind) {
        TrackKind.album => 'Album',
        TrackKind.podcast => 'Podcast',
        _ => 'Playlist',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = seed.browseUrl;
    final text = Theme.of(context).textTheme;

    if (url == null || url.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(seed.title)),
        body: const Center(child: Text('No playlist link for this result')),
      );
    }

    final async = ref.watch(_browseProvider(url));

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accentBright),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Sp.xl),
            child: Text('Could not load $_heading\n$e',
                textAlign: TextAlign.center, style: text.bodyMedium),
          ),
        ),
        data: (bundle) {
          final tracks = bundle.tracks;
          final title = bundle.title.isNotEmpty ? bundle.title : seed.title;
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                backgroundColor: AppColors.voidBlack,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.symmetric(
                      horizontal: Sp.xl, vertical: Sp.md),
                  title: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.artHeader(seed.accent),
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: seed.artworkUrl.isNotEmpty
                              ? Artwork(
                                  track: seed,
                                  size: 140,
                                  radius: BorderRadius.circular(12),
                                )
                              : Icon(
                                  seed.kind == TrackKind.podcast
                                      ? Icons.podcasts_rounded
                                      : Icons.queue_music_rounded,
                                  size: 72,
                                  color: Colors.white70,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
                  child: Row(
                    children: [
                      Text(
                        '$_heading · ${tracks.length} tracks',
                        style: text.labelLarge
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      if (tracks.isNotEmpty) ...[
                        IconButton(
                          tooltip: 'Save playlist',
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () async {
                            await ref
                                .read(playlistsProvider.notifier)
                                .createWith(title, tracks);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: AppColors.elevated,
                                content: Text(
                                  'Saved “$title” · ${tracks.length} tracks',
                                ),
                              ),
                            );
                          },
                        ),
                        FilledButton.icon(
                          onPressed: () {
                            ref
                                .read(playerControllerProvider.notifier)
                                .playQueue(tracks);
                            recordYoutubePlaylistPlay(
                              ref,
                              seed: seed,
                              title: title,
                              tracks: tracks,
                            );
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play all'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (tracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('No tracks in this list')),
                )
              else
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (_, i) => TrackTile(
                    track: tracks[i],
                    onTap: () {
                      ref
                          .read(playerControllerProvider.notifier)
                          .playQueue(tracks, startAt: i);
                      recordYoutubePlaylistPlay(
                        ref,
                        seed: seed,
                        title: title,
                        tracks: tracks,
                      );
                    },
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () =>
                          AddToPlaylistSheet.show(context, tracks[i]),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
    );
  }
}

final _browseProvider = FutureProvider.autoDispose
    .family<({String title, List<Track> tracks}), String>((ref, url) async {
  return ref.watch(musicRepositoryProvider).importPlaylist(url);
});
