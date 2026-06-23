import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../state/playlist_controller.dart';
import '../../state/player_controller.dart';
import '../../widgets/artwork.dart';
import '../../widgets/track_tile.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref
        .watch(playlistsProvider)
        .where((p) => p.id == playlistId)
        .firstOrNull;
    final text = Theme.of(context).textTheme;

    if (playlist == null) {
      return const Scaffold(body: Center(child: Text('Playlist removed')));
    }

    final tracks = playlist.tracks;
    final seed = tracks.isEmpty ? AppColors.accent : tracks.first.accent;
    final playing = ref.watch(playerControllerProvider).current;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: AppColors.voidBlack,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(playlist.name, style: text.titleLarge),
              titlePadding:
                  const EdgeInsets.symmetric(horizontal: Sp.xxl, vertical: Sp.lg),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [seed.withValues(alpha: 0.6), AppColors.voidBlack],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 150,
                      height: 150,
                      margin: const EdgeInsets.only(bottom: 40),
                      decoration: BoxDecoration(
                        borderRadius: Radii.rLg,
                        color: AppColors.elevated,
                        boxShadow: [
                          BoxShadow(
                              color: seed.withValues(alpha: 0.5),
                              blurRadius: 48,
                              spreadRadius: -10),
                        ],
                      ),
                      child: tracks.isEmpty
                          ? const Icon(Icons.queue_music_rounded,
                              size: 60, color: AppColors.textSecondary)
                          : ClipRRect(
                              borderRadius: Radii.rLg,
                              child:
                                  Artwork(track: tracks.first, size: 150)),
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
                  Expanded(
                    child: Text(
                      '${tracks.length} tracks · ${Fmt.duration(playlist.total)}',
                      style: text.bodyMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: tracks.isEmpty
                        ? null
                        : () => ref
                            .read(playerControllerProvider.notifier)
                            .playQueue(tracks, startAt: 0),
                    icon: const Icon(Icons.shuffle_rounded),
                    color: AppColors.textSecondary,
                  ),
                  _PlayAllButton(
                    enabled: tracks.isNotEmpty,
                    onTap: () => ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(tracks, startAt: 0),
                  ),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No tracks yet — add some from Search',
                    style: text.bodyMedium),
              ),
            )
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) => Dismissible(
                key: ValueKey(tracks[i].id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: Sp.xl),
                  color: Colors.red.withValues(alpha: 0.3),
                  child: const Icon(Icons.delete_outline_rounded),
                ),
                onDismissed: (_) => ref
                    .read(playlistsProvider.notifier)
                    .removeTrack(playlist.id, tracks[i].id),
                child: TrackTile(
                  track: tracks[i],
                  active: playing?.id == tracks[i].id,
                  onTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(tracks, startAt: i),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _PlayAllButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled ? AppColors.accentSweep : null,
          color: enabled ? null : AppColors.elevated,
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.5),
                      blurRadius: 24,
                      spreadRadius: -4),
                ]
              : null,
        ),
        child: Icon(Icons.play_arrow_rounded,
            color: enabled ? Colors.black : AppColors.textTertiary, size: 32),
      ),
    );
  }
}
