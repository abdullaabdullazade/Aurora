import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/dynamic_palette.dart';
import '../../state/player_controller.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';

/// What the listening log actually adds up to. Recents are capped and
/// reordered, so this reads the durable stats box instead.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(listeningStatsProvider);
    final text = Theme.of(context).textTheme;

    final totalSeconds =
        stats.fold<int>(0, (sum, s) => sum + s.secondsPlayed);
    final totalPlays = stats.fold<int>(0, (sum, s) => sum + s.count);

    final byArtist = <String, int>{};
    for (final s in stats) {
      byArtist[s.track.artist] =
          (byArtist[s.track.artist] ?? 0) + s.secondsPlayed;
    }
    final topArtists = byArtist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topTracks = [...stats]
      ..sort((a, b) => b.secondsPlayed.compareTo(a.secondsPlayed));

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      appBar: AppBar(
        title: const Text('Listening stats'),
        backgroundColor: Colors.transparent,
        actions: [
          if (stats.isNotEmpty)
            IconButton(
              tooltip: 'Reset',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ref.read(localStoreProvider).clearStats();
                ref.invalidate(listeningStatsProvider);
              },
            ),
        ],
      ),
      body: stats.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insights_rounded,
                      size: 56, color: AppColors.textTertiary),
                  const SizedBox(height: Sp.md),
                  Text('Nothing counted yet', style: text.titleMedium),
                  const SizedBox(height: Sp.xs),
                  Text('Play something and come back.',
                      style: text.bodyMedium),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 180),
              children: [
                Row(
                  children: [
                    _Stat(
                        value: _hours(totalSeconds),
                        label: 'listened',
                        icon: Icons.schedule_rounded),
                    const SizedBox(width: Sp.md),
                    _Stat(
                        value: '$totalPlays',
                        label: totalPlays == 1 ? 'play' : 'plays',
                        icon: Icons.play_arrow_rounded),
                    const SizedBox(width: Sp.md),
                    _Stat(
                        value: '${stats.length}',
                        label: 'tracks',
                        icon: Icons.music_note_rounded),
                  ],
                ),
                const SizedBox(height: Sp.xl),
                Text('Top artists', style: text.titleLarge),
                const SizedBox(height: Sp.sm),
                for (final a in topArtists.take(5))
                  _ArtistRow(
                    name: a.key,
                    seconds: a.value,
                    fraction: topArtists.first.value == 0
                        ? 0
                        : a.value / topArtists.first.value,
                  ),
                const SizedBox(height: Sp.xl),
                Text('Most played', style: text.titleLarge),
                const SizedBox(height: Sp.sm),
                for (final s in topTracks.take(20))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Artwork(track: s.track, size: 48),
                    title: Text(s.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall
                            ?.copyWith(color: AppColors.textPrimary)),
                    subtitle: Text(
                        '${s.count} ${s.count == 1 ? 'play' : 'plays'} · '
                        '${_hours(s.secondsPlayed)}',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textTertiary)),
                    onTap: () => ref
                        .read(playerControllerProvider.notifier)
                        .playSingle(s.track),
                  ),
              ],
            ),
    );
  }

  /// Minutes below an hour — "0.3 h listened" tells a new user nothing.
  static String _hours(int seconds) {
    if (seconds < 3600) return '${(seconds / 60).floor()} min';
    return '${(seconds / 3600).toStringAsFixed(1)} h';
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _Stat({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        decoration: BoxDecoration(
          borderRadius: Radii.rLg,
          border: Border.all(color: AppColors.glassStroke),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Tone.backdrop(AppColors.accent),
              AppColors.elevated,
            ],
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.accentBright),
            const SizedBox(height: 6),
            Text(value,
                style: text.titleMedium
                    ?.copyWith(color: AppColors.textPrimary)),
            Text(label,
                style: text.labelSmall
                    ?.copyWith(color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _ArtistRow extends StatelessWidget {
  final String name;
  final int seconds;
  final double fraction;
  const _ArtistRow(
      {required this.name, required this.seconds, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall
                        ?.copyWith(color: AppColors.textPrimary)),
              ),
              Text(StatsScreen._hours(seconds),
                  style: text.labelSmall
                      ?.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: Radii.rPill,
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.glassStroke,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.accentBright),
            ),
          ),
        ],
      ),
    );
  }
}
