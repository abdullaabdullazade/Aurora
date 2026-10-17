import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../state/auth_controller.dart';
import '../../state/connectivity_controller.dart';
import '../../state/playlist_controller.dart';
import '../../state/providers.dart';
import '../../widgets/aurora_refresh.dart';
import '../../widgets/glass.dart';
import '../../widgets/section_carousel.dart';
import '../library/playlist_detail_screen.dart';
import '../search/playlist_browse_screen.dart';
import '../settings/settings_screen.dart';
import '../../../domain/entities/playlist.dart';
import '../../../domain/entities/recent_playlist.dart';
import '../../../domain/entities/track.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// MRU recent playlists, filled up to 4 with library playlists when needed.
List<RecentPlaylist> _quickAccessPlaylists({
  required List<RecentPlaylist> recent,
  required List<Playlist> library,
}) {
  final out = <RecentPlaylist>[];
  final seen = <String>{};

  void add(RecentPlaylist item) {
    if (out.length >= 4) return;
    if (!seen.add(item.id)) return;
    if (item.libraryId != null) seen.add('lib:${item.libraryId}');
    out.add(item);
  }

  final byId = {for (final p in library) p.id: p};
  for (final r in recent) {
    final libraryId = r.libraryId;
    if (r.source == RecentPlaylistSource.library && libraryId != null) {
      // Deleted playlists drop out; renamed ones show their current name.
      final current = byId[libraryId];
      if (current == null) continue;
      add(RecentPlaylist.library(
        libraryId: current.id,
        title: current.name,
        artworkUrl: current.coverUrl ?? '',
        tracks: current.tracks,
      ));
      continue;
    }
    add(r);
  }
  for (final p in library) {
    if (out.length >= 4) break;
    add(
      RecentPlaylist.library(
        libraryId: p.id,
        title: p.name,
        artworkUrl: p.coverUrl ?? '',
        tracks: p.tracks,
      ),
    );
  }
  return out;
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forYou = ref.watch(forYouProvider);
    final playlistsForYou = ref.watch(playlistsForYouProvider);
    final trending = ref.watch(trendingProvider);
    final charts = ref.watch(topChartsProvider);
    final recent = ref.watch(recentlyPlayedProvider);
    final recentPlaylists = ref.watch(recentPlaylistsProvider);
    final libraryPlaylists = ref.watch(playlistsProvider);
    final quickAccessPlaylists = _quickAccessPlaylists(
      recent: recentPlaylists,
      library: libraryPlaylists,
    );
    final quickDownloads = ref.watch(quickDownloadsProvider);
    final online = ref.watch(isOnlineProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final text = Theme.of(context).textTheme;

    return AuroraRefresh(
      onRefresh: () async {
        ref.read(musicRepositoryProvider).invalidateRecommendationCaches();
        ref.invalidate(forYouProvider);
        ref.invalidate(playlistsForYouProvider);
        ref.invalidate(trendingProvider);
        ref.invalidate(topChartsProvider);
        ref.invalidate(quickDownloadsProvider);
        ref.invalidate(recentlyPlayedProvider);
        ref.read(syncRevisionProvider.notifier).state++;
        await Future.wait([
          ref.read(forYouProvider.future),
          ref.read(trendingProvider.future),
        ]);
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
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: Sp.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SettingsScreen())),
                  child: _ProfileAvatar(user: user),
                ),
              ),
            ),
            title: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: Sp.sm),
                child: Text('Aurora',
                    style: text.titleLarge?.copyWith(
                        color: AppColors.accentBright,
                        fontWeight: FontWeight.w800)),
              ),
            ),
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
          ),
          if (!online) const SliverToBoxAdapter(child: _OfflineSanctuary()),
          if (quickAccessPlaylists.isNotEmpty)
            SliverToBoxAdapter(
              child: _QuickPlaylistsGrid(items: quickAccessPlaylists),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: Sp.sm)),
          SliverToBoxAdapter(
            child: SectionCarousel(
              title: 'For you',
              data: forYou,
              cardSize: 168,
              emptyTitle: 'Nothing picked yet',
              emptySubtitle: 'Listen to a few tracks and we\'ll learn your taste.',
              onRetry: () => ref.invalidate(forYouProvider),
            ),
          ),
          SliverToBoxAdapter(
            child: SectionCarousel(
              title: 'Playlists for you',
              data: playlistsForYou,
              cardSize: 168,
              emptyTitle: 'No playlists yet',
              emptySubtitle: 'Pull down to refresh in a moment.',
              onRetry: () => ref.invalidate(playlistsForYouProvider),
            ),
          ),
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
              data: quickDownloads,
              cardSize: 140,
              emptyTitle: 'Nothing to download',
              emptySubtitle: 'Suggestions appear once For you loads.',
              onRetry: () => ref.invalidate(quickDownloadsProvider),
            ),
          ),
          // Bottom padding so content clears mini-player + nav bar.
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final providerPhoto = user?.providerData
        .where((profile) => profile.providerId == 'google.com')
        .map((profile) => profile.photoURL)
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .firstOrNull;
    final photoUrl =
        (user?.photoURL?.isNotEmpty ?? false) ? user!.photoURL : providerPhoto;
    final displayName = user?.displayName?.trim() ?? '';
    final fallback = displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
        : null;

    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(1.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentSweep,
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                key: ValueKey(photoUrl),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(fallback),
              )
            : _fallback(fallback),
      ),
    );
  }

  Widget _fallback(String? initial) => ColoredBox(
        color: AppColors.elevated,
        child: Center(
          child: initial != null
              ? Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.accentBright,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : const Icon(Icons.person_rounded,
                  color: AppColors.accentBright, size: 20),
        ),
      );
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Good evening';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
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
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${days[n.weekday - 1]}, ${mons[n.month - 1]} ${n.day}';
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
                  style:
                      text.labelLarge?.copyWith(color: AppColors.textPrimary)),
              const SizedBox(width: Sp.xs),
              Text('· downloads only', style: text.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spotify-style 2×2 quick access for recently played playlists.
class _QuickPlaylistsGrid extends ConsumerWidget {
  const _QuickPlaylistsGrid({required this.items});

  final List<RecentPlaylist> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = items.take(4).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final tileW = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in shown)
                SizedBox(
                  width: tileW,
                  height: 56,
                  child: _QuickPlaylistTile(item: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickPlaylistTile extends StatelessWidget {
  const _QuickPlaylistTile({required this.item});

  final RecentPlaylist item;

  void _open(BuildContext context) {
    if (item.source == RecentPlaylistSource.library &&
        item.libraryId != null &&
        item.libraryId!.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlistId: item.libraryId!),
        ),
      );
      return;
    }
    final url = item.browseUrl;
    if (url != null && url.isNotEmpty) {
      final seed = Track(
        id: item.id,
        title: item.title,
        artist: '',
        artworkUrl: item.artworkUrl,
        duration: Duration.zero,
        kind: TrackKind.playlist,
        browseUrl: url,
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistBrowseScreen(seed: seed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: AppColors.elevated,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: item.artworkUrl.isEmpty
                  ? ColoredBox(
                      color: AppColors.elevatedHi,
                      child: Icon(
                        Icons.queue_music_rounded,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 28,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.artworkUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 200),
                      placeholder: (_, __) =>
                          const ColoredBox(color: AppColors.elevatedHi),
                      errorWidget: (_, __, ___) => ColoredBox(
                        color: AppColors.elevatedHi,
                        child: Icon(
                          Icons.queue_music_rounded,
                          color: Colors.white.withValues(alpha: 0.7),
                          size: 28,
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
