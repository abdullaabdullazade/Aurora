import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  const ArtistDetailScreen(
      {super.key, required this.artist, this.accent = AppColors.accent});

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
            expandedHeight: 260,
            backgroundColor: AppColors.voidBlack,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(
                  horizontal: Sp.xl, vertical: Sp.lg),
              title: Text(artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineMedium),
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
                  Align(
                    alignment: const Alignment(0, -0.3),
                    child: Container(
                      width: 110,
                      height: 110,
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
                          color: Colors.black, size: 56),
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
