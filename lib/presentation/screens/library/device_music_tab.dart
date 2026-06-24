import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../state/device_music_controller.dart';
import '../../state/player_controller.dart';
import '../../widgets/glass.dart';
import 'folder_songs_screen.dart';

class DeviceMusicTab extends ConsumerWidget {
  const DeviceMusicTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(musicFoldersProvider);
    final hidden = ref.watch(hiddenFoldersProvider);
    final visible = ref.watch(visibleDeviceTracksProvider);
    final text = Theme.of(context).textTheme;

    return folders.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => _PermissionGate(
        onGrant: () => ref.invalidate(deviceSongsProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return _Empty(
            icon: Icons.library_music_outlined,
            title: 'No music on device',
            sub: 'Songs in your storage appear here',
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${visible.length} songs · ${list.length} folders',
                      style: text.bodyMedium,
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black),
                    onPressed: visible.isEmpty
                        ? null
                        : () => ref
                            .read(playerControllerProvider.notifier)
                            .playQueue(visible),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play all'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, 180),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: Sp.md),
                itemBuilder: (_, i) {
                  final f = list[i];
                  final isHidden = hidden.contains(f.path);
                  return _FolderCard(
                    name: f.name,
                    subtitle:
                        '${f.tracks.length} songs · ${Fmt.duration(f.total)}',
                    hidden: isHidden,
                    onTap: isHidden
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    FolderSongsScreen(folderPath: f.path),
                              ),
                            ),
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      ref
                          .read(hiddenFoldersProvider.notifier)
                          .toggle(f.path);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool hidden;
  final VoidCallback? onTap;
  final VoidCallback onToggle;
  const _FolderCard({
    required this.name,
    required this.subtitle,
    required this.hidden,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Opacity(
      opacity: hidden ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Glass(
          radius: Radii.rLg,
          padding: const EdgeInsets.all(Sp.md),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: Radii.rSm,
                  gradient: hidden ? null : AppColors.accentSweep,
                  color: hidden ? AppColors.elevated : null,
                ),
                child: Icon(
                  hidden ? Icons.folder_off_rounded : Icons.folder_rounded,
                  color: hidden ? AppColors.textSecondary : Colors.black,
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: text.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                onPressed: onToggle,
                icon: Icon(
                  hidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: hidden
                      ? AppColors.textSecondary
                      : AppColors.accentBright,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionGate extends StatelessWidget {
  final VoidCallback onGrant;
  const _PermissionGate({required this.onGrant});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_special_rounded,
                size: 64, color: AppColors.textTertiary),
            const SizedBox(height: Sp.md),
            Text('Allow access to your music', style: text.titleMedium),
            const SizedBox(height: Sp.xs),
            Text('Aurora needs permission to read audio files on this device',
                textAlign: TextAlign.center, style: text.bodyMedium),
            const SizedBox(height: Sp.lg),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black),
              onPressed: onGrant,
              child: const Text('Grant access'),
            ),
            const SizedBox(height: Sp.sm),
            TextButton(
              onPressed: () => openAppSettings(),
              child: Text('Open settings',
                  style: text.labelLarge
                      ?.copyWith(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _Empty(
      {required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: Sp.md),
          Text(title, style: text.titleMedium),
          const SizedBox(height: Sp.xs),
          Text(sub, style: text.bodyMedium),
        ],
      ),
    );
  }
}
