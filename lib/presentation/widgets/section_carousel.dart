import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/track.dart';
import '../screens/home/see_all_screen.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import 'skeletons.dart';
import 'track_card.dart';

/// Titled horizontal carousel fed by an async list. Renders shimmer while
/// loading, an inline error on failure, and tactile cards on success.
class SectionCarousel extends ConsumerWidget {
  final String title;
  final AsyncValue<List<Track>> data;
  final double cardSize;

  const SectionCarousel({
    super.key,
    required this.title,
    required this.data,
    this.cardSize = 150,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: text.titleLarge),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final list = data.valueOrNull ?? const [];
                  if (list.isEmpty) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SeeAllScreen(title: title, tracks: list),
                  ));
                },
                child: Text('See all',
                    style: text.labelLarge
                        ?.copyWith(color: AppColors.accentBright)),
              ),
            ],
          ),
        ),
        data.when(
          loading: () => CarouselSkeleton(cardSize: cardSize),
          error: (_, __) => _Error(height: cardSize + 52),
          data: (tracks) => SizedBox(
            height: cardSize + 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              physics: const BouncingScrollPhysics(),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: Sp.md),
              itemBuilder: (_, i) => RepaintBoundary(
                child: TrackCard(
                  track: tracks[i],
                  size: cardSize,
                  onTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(tracks, startAt: i),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Error extends ConsumerWidget {
  final double height;
  const _Error({required this.height});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 32, color: AppColors.textTertiary),
            const SizedBox(height: Sp.sm),
            Text('Can’t reach the server', style: text.bodyMedium),
            const SizedBox(height: Sp.xs),
            TextButton(
              onPressed: () {
                ref.invalidate(trendingProvider);
                ref.invalidate(recentlyPlayedProvider);
              },
              child: Text('Retry',
                  style: text.labelLarge
                      ?.copyWith(color: AppColors.accentBright)),
            ),
          ],
        ),
      ),
    );
  }
}
