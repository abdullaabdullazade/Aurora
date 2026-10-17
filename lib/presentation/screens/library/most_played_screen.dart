import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/track.dart';
import '../../state/download_controller.dart';
import '../../state/player_controller.dart';
import '../../state/providers.dart';
import '../../widgets/track_tile.dart';
import '../settings/stats_screen.dart';

/// Spotify "On Repeat"-style list built from listening stats, kept offline
/// by [mostPlayedOfflineSyncProvider] while the switch is on.
class MostPlayedScreen extends ConsumerWidget {
  const MostPlayedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final ranked = ref.watch(mostPlayedProvider);
    final allStats = ref.watch(listeningStatsProvider);
    final offline = ref.watch(offlineMostPlayedProvider);
    final jobs = ref.watch(downloadControllerProvider);
    final downloads = {
      for (final t in ref.watch(downloadsProvider).valueOrNull ?? const <Track>[])
        t.id: t,
    };
    final playingId =
        ref.watch(playerControllerProvider.select((s) => s.current?.id));

    // Stats rows carry no file path; use the offline copy where there is one
    // so these tracks play (and stay enabled) without a connection.
    final tracks = [for (final s in ranked) downloads[s.track.id] ?? s.track];
    final offlineCount = tracks.where((t) => t.isDownloaded).length;
    final totalSeconds =
        allStats.fold<int>(0, (sum, s) => sum + s.secondsPlayed);
    final totalPlays = allStats.fold<int>(0, (sum, s) => sum + s.count);

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: AppColors.voidBlack,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: 'Listening stats',
                icon: const Icon(Icons.insights_rounded),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StatsScreen())),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(
                  horizontal: Sp.xl, vertical: Sp.lg),
              title: Text('Most played', style: text.headlineMedium),
              background: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0E5A4A), AppColors.voidBlack],
                  ),
                ),
                child: Align(
                  alignment: Alignment(0, -0.3),
                  child: Icon(Icons.repeat_rounded,
                      size: 72, color: Colors.white70),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: Text(
                'You have listened ${Fmt.listened(totalSeconds)} · '
                '$totalPlays ${totalPlays == 1 ? 'play' : 'plays'}',
                style: text.titleMedium,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              activeThumbColor: AppColors.accentBright,
              title: Text('Keep offline', style: text.titleSmall),
              subtitle: Text(
                offline
                    ? '$offlineCount of ${tracks.length} downloaded · '
                        'updates on Wi‑Fi'
                    : 'Download these songs automatically on Wi‑Fi',
                style: text.bodySmall,
              ),
              value: offline,
              onChanged: (v) =>
                  ref.read(offlineMostPlayedProvider.notifier).set(v),
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.repeat_rounded,
                        size: 64, color: AppColors.textTertiary),
                    const SizedBox(height: Sp.md),
                    Text('Nothing on repeat yet', style: text.titleMedium),
                    const SizedBox(height: Sp.xs),
                    Text('Songs you play twice or more show up here',
                        style: text.bodyMedium),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${tracks.length} songs',
                          style: text.bodyMedium),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black),
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .playQueue(tracks),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) {
                final t = tracks[i];
                final plays = ranked[i].count;
                return TrackTile(
                  track: t,
                  active: playingId == t.id,
                  onTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(tracks, startAt: i),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$plays×',
                          style: text.labelMedium
                              ?.copyWith(color: AppColors.textTertiary)),
                      const SizedBox(width: Sp.sm),
                      if (jobs.containsKey(t.id))
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentBright),
                        )
                      else
                        Icon(
                          t.isDownloaded
                              ? Icons.download_done_rounded
                              : Icons.cloud_outlined,
                          size: 18,
                          color: t.isDownloaded
                              ? AppColors.accentBright
                              : AppColors.textTertiary,
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }
}
