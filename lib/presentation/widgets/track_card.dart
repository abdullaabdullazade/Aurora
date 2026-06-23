import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/track.dart';
import 'artwork.dart';

/// Vertical card for horizontal carousels. Scales down on press for tactility.
class TrackCard extends StatefulWidget {
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
  State<TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<TrackCard> {
  double _scale = 1;
  void _set(double v) => setState(() => _scale = v);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTapDown: (_) => _set(0.95),
      onTapCancel: () => _set(1),
      onTapUp: (_) => _set(1),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
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
