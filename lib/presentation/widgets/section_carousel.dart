import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/track.dart';
import '../screens/home/see_all_screen.dart';
import '../state/player_controller.dart';
import 'section_state_card.dart';
import 'skeletons.dart';
import 'track_card.dart';

/// Titled horizontal carousel fed by an async list. Renders shimmer while
/// loading, a card-framed message on failure or when empty, and tactile cards
/// on success. All three states occupy the same height so resolving the future
/// never shifts the page under the reader.
class SectionCarousel extends ConsumerWidget {
  final String title;
  final AsyncValue<List<Track>> data;
  final double cardSize;

  /// What "nothing here" means for this section, in its own words.
  final String emptyTitle;
  final String emptySubtitle;

  /// Refetches this section only. Without it the failure card shows no action.
  final VoidCallback? onRetry;

  const SectionCarousel({
    super.key,
    required this.title,
    required this.data,
    this.cardSize = 150,
    this.emptyTitle = 'Nothing here yet',
    this.emptySubtitle = 'Start listening and this fills up.',
    this.onRetry,
  });

  double get _height => cardSize + 52;

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
          error: (_, __) => SectionStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Unable to load ${title.toLowerCase()}',
            subtitle: 'Check your connection and try again.',
            onRetry: onRetry,
          ),
          data: (tracks) => tracks.isEmpty
              ? SectionStateCard(
                  icon: Icons.music_note_rounded,
                  title: emptyTitle,
                  subtitle: emptySubtitle,
                )
              : SizedBox(
                  height: _height,
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
