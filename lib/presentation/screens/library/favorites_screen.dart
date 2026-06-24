import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../state/favorites_controller.dart';
import '../../state/player_controller.dart';
import '../../widgets/track_tile.dart';

/// Liked Songs — the user's favorites, persisted in Hive.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(favoritesProvider);
    final playing = ref.watch(playerControllerProvider).current;
    final text = Theme.of(context).textTheme;
    final total =
        liked.fold(Duration.zero, (s, t) => s + t.duration);

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            backgroundColor: AppColors.voidBlack,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(
                  horizontal: Sp.xl, vertical: Sp.lg),
              title: Text('Liked Songs', style: text.headlineMedium),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3D1F6E), AppColors.voidBlack],
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, -0.35),
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        borderRadius: Radii.rLg,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF7C4DFF), AppColors.accentBright],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF7C4DFF)
                                  .withValues(alpha: 0.5),
                              blurRadius: 40,
                              spreadRadius: -6),
                        ],
                      ),
                      child: const Icon(Icons.favorite_rounded,
                          color: Colors.white, size: 52),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (liked.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_border_rounded,
                        size: 64, color: AppColors.textTertiary),
                    const SizedBox(height: Sp.md),
                    Text('No liked songs yet', style: text.titleMedium),
                    const SizedBox(height: Sp.xs),
                    Text('Tap the heart on any track', style: text.bodyMedium),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${liked.length} songs · ${Fmt.duration(total)}',
                        style: text.bodyMedium,
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black),
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .playQueue(liked),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: liked.length,
              itemBuilder: (_, i) => TrackTile(
                track: liked[i],
                active: playing?.id == liked[i].id,
                onTap: () => ref
                    .read(playerControllerProvider.notifier)
                    .playQueue(liked, startAt: i),
                trailing: IconButton(
                  icon: const Icon(Icons.favorite_rounded,
                      color: AppColors.accentBright),
                  onPressed: () =>
                      ref.read(favoritesProvider.notifier).toggle(liked[i]),
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }
}
