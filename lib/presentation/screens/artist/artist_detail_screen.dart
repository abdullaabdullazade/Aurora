import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/track.dart';
import '../../state/player_controller.dart';
import '../../state/providers.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/track_tile.dart';

/// Artist page: a big gradient header + the artist's top tracks (search-backed).
class ArtistDetailScreen extends ConsumerWidget {
  final String artist;
  final Color accent;
  final String? channelUrl;
  const ArtistDetailScreen(
      {super.key,
      required this.artist,
      this.accent = AppColors.accent,
      this.channelUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(artistTracksProvider(artist));
    final playing = ref.watch(playerControllerProvider).current;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 320,
            backgroundColor: AppColors.voidBlack,
            iconTheme: const IconThemeData(color: Colors.white),
            // Collapsed title sits clear of the back button (no overlap).
            title: Text(artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accent.withValues(alpha: 0.7),
                          AppColors.voidBlack
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 116,
                          height: 116,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.accentSweep,
                            boxShadow: [
                              BoxShadow(
                                  color: accent.withValues(alpha: 0.5),
                                  blurRadius: 40,
                                  spreadRadius: -6),
                            ],
                          ),
                          child: const Icon(Icons.person_rounded,
                              color: Colors.black, size: 58),
                        ),
                        const SizedBox(height: Sp.md),
                        Text(artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.headlineMedium),
                        const SizedBox(height: Sp.sm),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.glassStroke),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () {
                            // Real channel page when known, else a search.
                            final uri = Uri.parse(channelUrl ??
                                'https://www.youtube.com/results?search_query=${Uri.encodeComponent(artist)}');
                            launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text('View on YouTube'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          tracks.when(
            loading: () => const SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.only(top: Sp.xl),
                    child: CarouselSkeleton(cardSize: 120))),
            error: (_, __) => SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.all(Sp.xl),
                    child: Center(
                        child: Text('Couldn’t load', style: text.bodyMedium)))),
            data: (list) => _Body(
              list: list,
              playingId: playing?.id,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final List<Track> list;
  final String? playingId;
  const _Body({required this.list, required this.playingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (list.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(Sp.xl),
          child: Center(child: Text('No tracks found')),
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
            child: Row(
              children: [
                Text('Top tracks',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black),
                  onPressed: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(list),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => TrackTile(
            track: list[i],
            active: playingId == list[i].id,
            onTap: () => ref
                .read(playerControllerProvider.notifier)
                .playQueue(list, startAt: i),
          ),
        ),
      ],
    );
  }
}
