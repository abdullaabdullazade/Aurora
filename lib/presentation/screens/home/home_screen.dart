import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../state/connectivity_controller.dart';
import '../../state/favorites_controller.dart';
import '../../state/providers.dart';
import '../../widgets/aurora_refresh.dart';
import '../../widgets/glass.dart';
import '../../widgets/section_carousel.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(trendingProvider);
    final charts = ref.watch(topChartsProvider);
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
            expandedHeight: 156,
            backgroundColor: AppColors.voidBlack,
            surfaceTintColor: Colors.transparent,
            title: Text('Aurora',
                style: text.titleLarge?.copyWith(
                    color: AppColors.accentBright,
                    fontWeight: FontWeight.w800)),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, 44, Sp.lg, Sp.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Eyebrow: icon + weekday/date.
                      Row(children: [
                        Icon(_greetIcon(),
                            size: 15, color: AppColors.accentBright),
                        const SizedBox(width: 6),
                        Text(_todayLabel().toUpperCase(),
                            style: text.labelSmall?.copyWith(
                                color: AppColors.textTertiary,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 2),
                      // Greeting with a soft white→accent gradient.
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.textPrimary,
                            AppColors.accentBright,
                          ],
                        ).createShader(b),
                        child: Text(_greeting(),
                            style: text.displayLarge?.copyWith(
                                letterSpacing: -1, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: () =>
                    ref.read(navIndexProvider.notifier).state = 1,
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                onPressed: () => _showNotifications(context, ref),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              Padding(
                padding: const EdgeInsets.only(right: Sp.lg, left: Sp.xs),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SettingsScreen())),
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
              ),
            ],
          ),
          if (!online)
            const SliverToBoxAdapter(child: _OfflineSanctuary()),
          const SliverToBoxAdapter(child: SizedBox(height: Sp.sm)),
          // Each section retries only its own provider — a failed carousel
          // should not refetch (or wipe) the ones that loaded fine.
          SliverToBoxAdapter(
            child: SectionCarousel(
              title: 'Trending now',
              data: trending,
              cardSize: 168,
              emptyTitle: 'No trends right now',
              emptySubtitle: 'Pull down to refresh in a moment.',
              onRetry: () => ref.invalidate(trendingProvider),
            ),
          ),
          SliverToBoxAdapter(
            child: SectionCarousel(
              title: '🔥 Top Charts',
              data: charts,
              cardSize: 168,
              emptyTitle: 'Charts are empty',
              emptySubtitle: 'Nothing came back from the server.',
              onRetry: () => ref.invalidate(topChartsProvider),
            ),
          ),
          SliverToBoxAdapter(
            child: SectionCarousel(
              title: 'Recently played',
              data: recent,
              cardSize: 140,
              emptyTitle: 'Nothing here yet',
              emptySubtitle:
                  'Start listening and your recent tracks land here.',
              onRetry: () => ref.invalidate(recentlyPlayedProvider),
            ),
          ),
          SliverToBoxAdapter(
            child: SectionCarousel(
              title: 'Quick downloads',
              data: trending,
              cardSize: 140,
              emptyTitle: 'Nothing to download',
              emptySubtitle: 'Suggestions appear once trends load.',
              onRetry: () => ref.invalidate(trendingProvider),
            ),
          ),
          // Bottom padding so content clears mini-player + nav bar.
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Good night';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  if (h < 21) return 'Good evening';
  return 'Good night';
}

IconData _greetIcon() {
  final h = DateTime.now().hour;
  if (h < 5 || h >= 21) return Icons.nightlight_round;
  if (h < 12) return Icons.wb_twilight_rounded;
  if (h < 17) return Icons.wb_sunny_rounded;
  return Icons.nights_stay_rounded;
}

String _todayLabel() {
  final n = DateTime.now();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mons = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${days[n.weekday - 1]}, ${mons[n.month - 1]} ${n.day}';
}

void _showNotifications(BuildContext context, WidgetRef ref) {
  final text = Theme.of(context).textTheme;
  // Build from real state, not random placeholders.
  final recents = ref.read(recentlyPlayedProvider).valueOrNull ?? const [];
  final likedCount = ref.read(favoritesProvider).length;
  final items = <(IconData, String, String)>[
    if (recents.isNotEmpty)
      (Icons.history_rounded, 'Continue listening',
          'Pick up “${recents.first.title}”'),
    if (likedCount > 0)
      (Icons.favorite_rounded, 'Liked Songs',
          'You have $likedCount liked ${likedCount == 1 ? 'song' : 'songs'}'),
    (Icons.local_fire_department_rounded, 'Top Charts',
        'See what’s trending today'),
    (Icons.bedtime_rounded, 'Daily reminders on',
        'Mix at 12:30 · wind-down at 20:00'),
  ];
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Glass(
      radius: const BorderRadius.vertical(top: Radii.xl),
      blur: 30,
      opacity: 0.16,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Sp.md),
            Container(
                width: 44,
                height: 4,
                decoration: const BoxDecoration(
                    color: AppColors.glassStroke, borderRadius: Radii.rPill)),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Notifications', style: text.titleLarge)),
            ),
            for (final (icon, title, body) in items)
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      borderRadius: Radii.rSm,
                      gradient: AppColors.accentSweep),
                  child: Icon(icon, color: Colors.black, size: 20),
                ),
                title: Text(title, style: text.titleMedium),
                subtitle: Text(body, style: text.bodyMedium),
              ),
            const SizedBox(height: Sp.md),
          ],
        ),
      ),
    ),
  );
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
