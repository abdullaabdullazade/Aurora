import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/track.dart';
import '../state/connectivity_controller.dart';
import '../screens/library/track_context_sheet.dart';
import 'artwork.dart';

/// Horizontal row used in lists/queues. Highlights when [active]. Offline,
/// non-downloaded rows fade to 40% and stop responding to taps.
class TrackTile extends ConsumerWidget {
  final Track track;
  final bool active;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? leading;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.active = false,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final disabled = !ref.watch(isOnlineProvider) && !track.isDownloaded;
    return IgnorePointer(
      ignoring: disabled,
      child: AnimatedOpacity(
        opacity: disabled ? 0.4 : 1,
        duration: const Duration(milliseconds: 400),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
        borderRadius: Radii.rMd,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          TrackContextSheet.show(context, track);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.sm, vertical: Sp.sm),
          child: Row(
            children: [
              leading ??
                  Artwork(track: track, size: 52, radius: Radii.rSm),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        color: active
                            ? AppColors.accentBright
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (track.isDownloaded) ...[
                          const Icon(Icons.arrow_circle_down_rounded,
                              size: 13, color: AppColors.accent),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              trailing ??
                  Text(Fmt.duration(track.duration),
                      style: text.labelSmall),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}
