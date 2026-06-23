import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../state/providers.dart';
import '../../widgets/section_carousel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(trendingProvider);
    final recent = ref.watch(recentlyPlayedProvider);
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      color: AppColors.accentBright,
      backgroundColor: AppColors.elevated,
      onRefresh: () async {
        ref.invalidate(trendingProvider);
        ref.invalidate(recentlyPlayedProvider);
        await ref.read(trendingProvider.future);
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 132,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.only(left: Sp.lg, bottom: Sp.md),
              title: Text('Good evening',
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              background: Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, 64, Sp.lg, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text('Aurora',
                      style: text.displayLarge?.copyWith(
                          color: AppColors.accentBright, letterSpacing: -1)),
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              Padding(
                padding: const EdgeInsets.only(right: Sp.lg, left: Sp.xs),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentSweep,
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Colors.black, size: 20),
                ),
              ),
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Sp.sm)),
          SliverToBoxAdapter(
            child: SectionCarousel(
                title: 'Trending now', data: trending, cardSize: 168),
          ),
          SliverToBoxAdapter(
            child: SectionCarousel(
                title: 'Recently played', data: recent, cardSize: 140),
          ),
          SliverToBoxAdapter(
            child: SectionCarousel(
                title: 'Quick downloads', data: trending, cardSize: 140),
          ),
          // Bottom padding so content clears mini-player + nav bar.
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }
}
