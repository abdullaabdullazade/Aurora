import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/track.dart';
import '../state/player_controller.dart';
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
              Text('See all',
                  style: text.labelLarge
                      ?.copyWith(color: AppColors.textSecondary)),
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

class _Error extends StatelessWidget {
  final double height;
  const _Error({required this.height});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(
          child: Text('Couldn’t load',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}
