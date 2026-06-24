import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/track.dart';
import '../../state/player_controller.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/track_tile.dart';

/// Album page (search-backed): big cover + tracklist.
class AlbumDetailScreen extends ConsumerWidget {
  final Track seed; // the track that opened the album
  const AlbumDetailScreen({super.key, required this.seed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = '${seed.artist} ${seed.title} album';
    final tracks = ref.watch(artistTracksProvider(query));
    final playing = ref.watch(playerControllerProvider).current;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: AppColors.voidBlack,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(
                  horizontal: Sp.xl, vertical: Sp.md),
              title: Text(seed.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          seed.accent.withValues(alpha: 0.65),
                          AppColors.voidBlack
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 36),
                      decoration: BoxDecoration(
                        borderRadius: Radii.rLg,
                        boxShadow: [
                          BoxShadow(
                              color: seed.accent.withValues(alpha: 0.5),
                              blurRadius: 48,
                              spreadRadius: -10),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: Radii.rLg,
                        child: Artwork(track: seed, size: 168),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          tracks.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(Sp.xl),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accentBright)),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.all(Sp.xl),
                    child: Center(child: Text('Couldn’t load')))),
            data: (list) => SliverList.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => TrackTile(
                track: list[i],
                active: playing?.id == list[i].id,
                onTap: () => ref
                    .read(playerControllerProvider.notifier)
                    .playQueue(list, startAt: i),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }
}
