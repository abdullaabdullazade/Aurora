import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/track.dart';
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
      await Share.shareXFiles(
        [XFile(track.localPath!)],
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
                      artist: track.artist, accent: track.accent)),
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
