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

/// Vertical card for horizontal carousels. Scales down on press for tactility.
/// When offline, non-downloaded tracks fade to 40% and become unclickable.
class TrackCard extends ConsumerStatefulWidget {
  final Track track;
  final double size;
  final VoidCallback onTap;
  const TrackCard({
    super.key,
    required this.track,
    required this.onTap,
    this.size = 150,
  });

  @override
  ConsumerState<TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends ConsumerState<TrackCard> {
  double _scale = 1;
  void _set(double v) => setState(() => _scale = v);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final offline = !ref.watch(isOnlineProvider);
    final disabled = offline && !widget.track.isDownloaded;
    return IgnorePointer(
      ignoring: disabled,
      child: AnimatedOpacity(
        opacity: disabled ? 0.4 : 1,
        duration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTapDown: (_) => _set(0.95),
          onTapCancel: () => _set(1),
          onTapUp: (_) => _set(1),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            TrackContextSheet.show(context, widget.track);
          },
          child: AnimatedScale(
            scale: _scale,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: SizedBox(
          width: widget.size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Artwork(
                    track: widget.track,
                    size: widget.size,
                    radius: Radii.rLg,
                    glow: true,
                  ),
                  Positioned(
                    right: Sp.sm,
                    bottom: Sp.sm,
                    child: _PlayBadge(color: widget.track.accent),
                  ),
                ],
              ),
              const SizedBox(height: Sp.sm),
              Text(widget.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.headphones_rounded,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${widget.track.artist} · ${Fmt.compact(widget.track.plays)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  final Color color;
  const _PlayBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentSweep,
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 16,
              spreadRadius: -2),
        ],
      ),
      child: const Icon(Icons.play_arrow_rounded,
          color: Colors.black, size: 24),
    );
  }
}
