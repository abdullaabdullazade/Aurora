import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/track.dart';
import '../../state/playlist_controller.dart';
import '../../widgets/glass.dart';

/// Bottom sheet: add [track] to an existing playlist or create a new one.
class AddToPlaylistSheet extends ConsumerWidget {
  final Track track;
  const AddToPlaylistSheet({super.key, required this.track});

  static Future<void> show(BuildContext context, Track track) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => AddToPlaylistSheet(track: track),
      );

  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    final name = await _askName(context);
    if (name == null || name.trim().isEmpty) return;
    final pl = await ref.read(playlistsProvider.notifier).create(name);
    await ref.read(playlistsProvider.notifier).addTrack(pl.id, track);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final text = Theme.of(context).textTheme;

    return Glass(
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
                    color: AppColors.glassStroke,
                    borderRadius: Radii.rPill)),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Row(children: [
                Text('Add to playlist', style: text.titleLarge),
              ]),
            ),
            ListTile(
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                    borderRadius: Radii.rSm, gradient: AppColors.accentSweep),
                child: const Icon(Icons.add_rounded, color: Colors.black),
              ),
              title: Text('New playlist', style: text.titleMedium),
              onTap: () => _createAndAdd(context, ref),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: Sp.lg),
                itemCount: playlists.length,
                itemBuilder: (_, i) {
                  final p = playlists[i];
                  return ListTile(
                    leading: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: Radii.rSm,
                        color: AppColors.elevated,
                      ),
                      child: const Icon(Icons.queue_music_rounded,
                          color: AppColors.textSecondary),
                    ),
                    title: Text(p.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${p.tracks.length} tracks',
                        style: text.labelSmall),
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      await ref
                          .read(playlistsProvider.notifier)
                          .addTrack(p.id, track);
                      if (context.mounted) Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName(BuildContext context) => showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            backgroundColor: AppColors.elevated,
            shape: const RoundedRectangleBorder(borderRadius: Radii.rLg),
            title: const Text('New playlist'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              cursorColor: AppColors.accentBright,
              decoration: const InputDecoration(hintText: 'Playlist name'),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent),
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
}
