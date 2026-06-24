import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/playlist.dart';
import '../../../domain/entities/track.dart';
import '../../state/player_controller.dart';
import '../../state/playlist_controller.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass.dart';
import '../../widgets/track_tile.dart';
import '../../state/favorites_controller.dart';
import '../../state/download_controller.dart';
import 'device_music_tab.dart';
import 'favorites_screen.dart';
import 'playlist_detail_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
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
            child: Row(
              children: [
                Text('Your Library', style: text.displayLarge),
                const Spacer(),
                _NewPlaylistButton(
                    onCreated: (id) => _open(context, id)),
              ],
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
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'On device'),
              Tab(text: 'Downloaded'),
              Tab(text: 'Queue'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _PlaylistsTab(onOpen: (id) => _open(context, id)),
                const DeviceMusicTab(),
                _DownloadedTab(
                  data: downloads,
                  filter: _filter,
                  onFilter: (v) => setState(() => _filter = v),
                ),
                const _DownloadingTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, String id) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaylistDetailScreen(playlistId: id),
    ));
  }
}

class _NewPlaylistButton extends ConsumerWidget {
  final ValueChanged<String> onCreated;
  const _NewPlaylistButton({required this.onCreated});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.add_circle_outline_rounded,
          color: AppColors.textPrimary, size: 28),
      onPressed: () async {
        final name = await _askName(context);
        if (name == null || name.trim().isEmpty) return;
        final p = await ref.read(playlistsProvider.notifier).create(name);
        onCreated(p.id);
      },
    );
  }

  Future<String?> _askName(BuildContext context) => showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            backgroundColor: AppColors.elevated,
            shape: const RoundedRectangleBorder(borderRadius: Radii.rLg),
            title: const Text('New playlist',
                style: TextStyle(color: AppColors.textPrimary)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              cursorColor: AppColors.accentBright,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Playlist name',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.glassStroke)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accentBright)),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.accent),
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
}

class _PlaylistsTab extends ConsumerWidget {
  final ValueChanged<String> onOpen;
  const _PlaylistsTab({required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final likedCount = ref.watch(favoritesProvider).length;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 180),
      itemCount: playlists.length + 1, // + pinned Liked Songs
      separatorBuilder: (_, __) => const SizedBox(height: Sp.md),
      itemBuilder: (context, i) {
        if (i == 0) {
          return _LikedSongsRow(
            count: likedCount,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const FavoritesScreen())),
          );
        }
        final p = playlists[i - 1];
        return _PlaylistRow(
          playlist: p,
          onTap: () => onOpen(p.id),
          onDelete: () => ref.read(playlistsProvider.notifier).delete(p.id),
        );
      },
    );
  }
}

class _LikedSongsRow extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _LikedSongsRow({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Glass(
        radius: Radii.rLg,
        padding: const EdgeInsets.all(Sp.md),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: Radii.rSm,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7C4DFF), AppColors.accentBright],
                ),
              ),
              child: const Icon(Icons.favorite_rounded, color: Colors.white),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Liked Songs', style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text('$count songs', style: text.bodyMedium),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PlaylistRow(
      {required this.playlist, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Glass(
        radius: Radii.rLg,
        padding: const EdgeInsets.all(Sp.md),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: Radii.rSm,
                gradient: playlist.tracks.isEmpty
                    ? AppColors.accentSweep
                    : null,
                color: AppColors.elevated,
              ),
              child: playlist.tracks.isEmpty
                  ? const Icon(Icons.queue_music_rounded, color: Colors.black)
                  : ClipRRect(
                      borderRadius: Radii.rSm,
                      child: Artwork(track: playlist.tracks.first, size: 56),
                    ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text('${playlist.tracks.length} tracks',
                      style: text.bodyMedium),
                ],
              ),
            ),
            PopupMenuButton<String>(
              color: AppColors.elevated,
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textSecondary),
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
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
    final text = Theme.of(context).textTheme;
    return data.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (_, __) => const Center(child: Text('Error')),
      data: (all) {
        final tracks = filter.isEmpty
            ? all
            : all
                .where((t) =>
                    t.title.toLowerCase().contains(filter.toLowerCase()) ||
                    t.artist.toLowerCase().contains(filter.toLowerCase()))
                .toList();
        if (all.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.download_done_rounded,
                    size: 64, color: AppColors.textTertiary),
                const SizedBox(height: Sp.md),
                Text('No downloads yet', style: text.titleMedium),
                const SizedBox(height: Sp.xs),
                Text('Downloaded tracks play offline', style: text.bodyMedium),
              ],
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Glass(
                radius: Radii.rPill,
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: TextField(
                  onChanged: onFilter,
                  style: text.bodyLarge,
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

/// Live download queue — shows in-flight downloads with progress.
class _DownloadingTab extends ConsumerWidget {
  const _DownloadingTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(downloadControllerProvider);
    final text = Theme.of(context).textTheme;
    if (jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_download_outlined,
                size: 64, color: AppColors.textTertiary),
            const SizedBox(height: Sp.md),
            Text('Download queue is empty', style: text.titleMedium),
            const SizedBox(height: Sp.xs),
            Text('Long-press a track → Download', style: text.bodyMedium),
          ],
        ),
      );
    }
    final entries = jobs.entries.toList();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 180),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: Sp.md),
      itemBuilder: (_, i) {
        final pct = entries[i].value;
        return Glass(
          radius: Radii.rLg,
          padding: const EdgeInsets.all(Sp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.downloading_rounded,
                      color: AppColors.accentBright),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                      child: Text('Downloading…', style: text.titleMedium)),
                  Text('${(pct * 100).round()}%', style: text.labelSmall),
                ],
              ),
              const SizedBox(height: Sp.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct == 0 ? null : pct,
                  minHeight: 5,
                  backgroundColor: AppColors.glassStroke,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.accentBright),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
