import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/app_config.dart';
import '../../../core/ringtone/ringtone_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/track.dart';
import '../../state/download_controller.dart';
import '../../state/player_controller.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';
import 'add_to_playlist_sheet.dart';

/// Long-press menu for a track: artist / album / playlist / share.
class TrackContextSheet extends ConsumerWidget {
  final Track track;
  const TrackContextSheet({super.key, required this.track});

  static Future<void> show(BuildContext context, Track track) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => TrackContextSheet(track: track),
      );

  Future<void> _share() async {
    if (track.localPath != null) {
      final safe = track.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      await Share.shareXFiles(
        [
          XFile(track.localPath!,
              name: '$safe.m4a', mimeType: 'audio/mp4')
        ],
        text: '${track.title} — ${track.artist}',
      );
    } else {
      await Share.share(
        '🎧 ${track.title} — ${track.artist}\nhttps://youtu.be/${track.id}',
      );
    }
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _setRingtone(BuildContext context, RingtoneType type) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    final svc = RingtoneService.instance;
    final ok = await svc.set(track.id, type);
    if (ok) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.elevated,
        content: Text('Set as ${type.name}: ${track.title}'),
      ));
    } else {
      // Needs the "modify system settings" permission.
      await svc.openWriteSettings();
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.elevated,
        content: Text('Allow “Modify system settings”, then try again'),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    color: AppColors.glassStroke, borderRadius: Radii.rPill)),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Row(
                children: [
                  Artwork(track: track, size: 52, radius: Radii.rSm),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium),
                        Text(track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (track.localPath == null)
              _Item(
                icon: Icons.download_rounded,
                label: 'Download (MP3 + lyrics)',
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(downloadControllerProvider.notifier)
                      .download(track);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.elevated,
                      elevation: 8,
                      margin: const EdgeInsets.all(Sp.lg),
                      shape: const RoundedRectangleBorder(
                          borderRadius: Radii.rPill),
                      duration: const Duration(seconds: 2),
                      content: Row(
                        children: [
                          const Icon(Icons.downloading_rounded,
                              color: AppColors.accentBright, size: 20),
                          const SizedBox(width: Sp.md),
                          Expanded(
                            child: Text('Downloading “${track.title}”',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ));
                },
              ),
            if (AppConfig.radioEnabled)
            _Item(
              icon: Icons.radio_rounded,
              label: 'Start radio',
              onTap: () {
                Navigator.pop(context);
                HapticFeedback.selectionClick();
                ref
                    .read(playerControllerProvider.notifier)
                    .startRadio(track);
              },
            ),
            _Item(
              icon: Icons.playlist_add_rounded,
              label: 'Add to playlist',
              onTap: () {
                Navigator.pop(context);
                AddToPlaylistSheet.show(context, track);
              },
            ),
            _Item(
              icon: Icons.person_rounded,
              label: 'Go to artist',
              onTap: () => _push(
                  context,
                  ArtistDetailScreen(
                      artist: track.artist,
                      accent: track.accent,
                      channelUrl: track.channelUrl)),
            ),
            _Item(
              icon: Icons.album_rounded,
              label: 'Go to album',
              onTap: () =>
                  _push(context, AlbumDetailScreen(seed: track)),
            ),
            _Item(
              icon: Icons.ios_share_rounded,
              label: track.localPath != null ? 'Share file' : 'Share link',
              onTap: () {
                HapticFeedback.selectionClick();
                _share();
              },
            ),
            if (track.localPath != null) ...[
              const Divider(height: 1, color: AppColors.glassStroke),
              _Item(
                icon: Icons.notifications_active_rounded,
                label: 'Set as ringtone',
                onTap: () => _setRingtone(context, RingtoneType.ringtone),
              ),
              _Item(
                icon: Icons.alarm_rounded,
                label: 'Set as alarm',
                onTap: () => _setRingtone(context, RingtoneType.alarm),
              ),
            ],
            const SizedBox(height: Sp.md),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Item(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(label, style: Theme.of(context).textTheme.titleMedium),
      onTap: onTap,
    );
  }
}
