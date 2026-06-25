import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../state/device_music_controller.dart';
import '../../state/player_controller.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/track_tile.dart';

/// Lists the songs inside one device folder.
class FolderSongsScreen extends ConsumerWidget {
  final String folderPath;
  const FolderSongsScreen({super.key, required this.folderPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(musicFoldersProvider).valueOrNull ?? const [];
    final folder = folders.where((f) => f.path == folderPath).firstOrNull;
    final playing = ref.watch(playerControllerProvider).current;
    final text = Theme.of(context).textTheme;

    if (folder == null) {
      return const Scaffold(body: Center(child: Text('Folder unavailable')));
    }
    final tracks = folder.tracks;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: AppColors.voidBlack,
        title: Text(folder.name,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleLarge),
      ),
      body: Stack(
        children: [
          CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${tracks.length} songs · ${Fmt.duration(folder.total)}',
                      style: text.bodyMedium,
                    ),
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
            itemBuilder: (_, i) => TrackTile(
              track: tracks[i],
              active: playing?.id == tracks[i].id,
              onTap: () => ref
                  .read(playerControllerProvider.notifier)
                  .playQueue(tracks, startAt: i),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
          ),
          // Mini-player pinned to the bottom so local/download playback is
          // controllable here too (this screen is pushed over the root shell).
          const Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
    );
  }
}
