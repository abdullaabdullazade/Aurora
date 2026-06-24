import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../state/connectivity_controller.dart';
import '../../state/providers.dart';
import '../../widgets/aurora_refresh.dart';
import '../../widgets/glass.dart';
import '../../widgets/section_carousel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(trendingProvider);
    final recent = ref.watch(recentlyPlayedProvider);
    final online = ref.watch(isOnlineProvider);
    final text = Theme.of(context).textTheme;

    return AuroraRefresh(
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
          if (!online)
            const SliverToBoxAdapter(child: _OfflineSanctuary()),
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

/// Breathing offline indicator near the header.
class _OfflineSanctuary extends StatefulWidget {
  const _OfflineSanctuary();
  @override
  State<_OfflineSanctuary> createState() => _OfflineSanctuaryState();
}

class _OfflineSanctuaryState extends State<_OfflineSanctuary>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Glass(
          radius: Radii.rPill,
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
                child: const Icon(Icons.cloud_off_rounded,
                    size: 16, color: AppColors.accentBright),
              ),
              const SizedBox(width: Sp.sm),
              Text('Offline Sanctuary',
                  style: text.labelLarge
                      ?.copyWith(color: AppColors.textPrimary)),
              const SizedBox(width: Sp.xs),
              Text('· downloads only', style: text.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
