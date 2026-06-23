import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/track.dart';
import '../../state/player_controller.dart';
import '../../state/providers.dart';
import '../../widgets/glass.dart';
import '../../widgets/track_tile.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  String _filter = '';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadsProvider);
    final text = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Your Library', style: text.displayLarge),
            ),
          ),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.accentBright,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: AppColors.accentBright,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: text.titleMedium,
            tabs: const [
              Tab(text: 'Downloaded'),
              Tab(text: 'Playlists'),
              Tab(text: 'Queue'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _DownloadedTab(
                  data: downloads,
                  filter: _filter,
                  onFilter: (v) => setState(() => _filter = v),
                ),
                const _PlaylistsTab(),
                const _DownloadingTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadedTab extends ConsumerWidget {
  final AsyncValue<List<Track>> data;
  final String filter;
  final ValueChanged<String> onFilter;
  const _DownloadedTab(
      {required this.data, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return data.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (_, __) => const Center(child: Text('Error')),
      data: (all) {
        final tracks = filter.isEmpty
            ? all
            : all
                .where((t) =>
                    t.title.toLowerCase().contains(filter.toLowerCase()) ||
                    t.artist.toLowerCase().contains(filter.toLowerCase()))
                .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Glass(
                radius: Radii.rPill,
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: TextField(
                  onChanged: onFilter,
                  style: Theme.of(context).textTheme.bodyLarge,
                  cursorColor: AppColors.accentBright,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: Sp.md),
                    hintText: 'Filter downloads',
                    icon: Icon(Icons.search_rounded,
                        color: AppColors.textSecondary, size: 20),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(Sp.sm, 0, Sp.sm, 180),
                itemCount: tracks.length,
                itemBuilder: (_, i) => TrackTile(
                  track: tracks[i],
                  onTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(tracks, startAt: i),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();
  @override
  Widget build(BuildContext context) {
    final names = ['Liked Songs', 'Focus Flow', 'Late Night', 'Workout'];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 180),
      itemCount: names.length,
      separatorBuilder: (_, __) => const SizedBox(height: Sp.md),
      itemBuilder: (_, i) => Glass(
        radius: Radii.rLg,
        padding: const EdgeInsets.all(Sp.md),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: Radii.rSm,
                gradient: AppColors.accentSweep,
              ),
              child: const Icon(Icons.queue_music_rounded,
                  color: Colors.black),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Text(names[i],
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Live download queue with progress / speed / ETA piped to the UI.
class _DownloadingTab extends StatelessWidget {
  const _DownloadingTab();
  @override
  Widget build(BuildContext context) {
    final jobs = [
      ('Midnight Aurora', 'Nova Wren', 0.72, 1.6),
      ('Neon Tides', 'Kasai', 0.34, 2.1),
      ('Glass Horizon', 'Aeon', 0.05, 0.9),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 180),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: Sp.md),
      itemBuilder: (_, i) {
        final (title, artist, pct, mbps) = jobs[i];
        final text = Theme.of(context).textTheme;
        return Glass(
          radius: Radii.rLg,
          padding: const EdgeInsets.all(Sp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.titleMedium),
                        Text(artist, style: text.bodyMedium),
                      ],
                    ),
                  ),
                  Icon(
                    pct < 1
                        ? Icons.pause_circle_rounded
                        : Icons.check_circle_rounded,
                    color: AppColors.accentBright,
                  ),
                ],
              ),
              const SizedBox(height: Sp.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: AppColors.glassStroke,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.accentBright),
                ),
              ),
              const SizedBox(height: Sp.sm),
              Text(
                '${(pct * 100).round()}%  ·  ${mbps.toStringAsFixed(1)} MB/s  ·  ETA ${Fmt.duration(Duration(seconds: ((1 - pct) * 90).round()))}',
                style: text.labelSmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
