import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/dynamic_palette.dart';

/// The non-content states of a section (failed / empty), rendered as one card
/// instead of loose text floating in dead space.
///
/// The card hugs its content instead of matching the carousel height: a state
/// card stretched to a 168px row's height is mostly padding, which reads as
/// unfinished — the exact problem it exists to solve.
class SectionStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// Omitted on empty states — there is nothing to retry.
  final VoidCallback? onRetry;

  const SectionStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tint = Tone.backdrop(AppColors.accent);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: Radii.rLg,
          border: Border.all(color: AppColors.glassStroke),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint, AppColors.elevated],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The aurora rings live here, inside the card and barely visible —
            // identity without eating the layout.
            Positioned.fill(
              child: CustomPaint(painter: const _RingsPainter()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.lg, vertical: Sp.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accentSoft,
                      border: Border.all(
                          color: AppColors.accentBright
                              .withValues(alpha: 0.35)),
                    ),
                    child: Icon(icon,
                        size: 20, color: AppColors.accentBright),
                  ),
                  const SizedBox(height: Sp.sm),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: text.titleSmall
                          ?.copyWith(color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      textAlign: TextAlign.center,
                      style: text.bodySmall
                          ?.copyWith(color: AppColors.textTertiary)),
                  if (onRetry != null) ...[
                    const SizedBox(height: Sp.sm),
                    AuroraPill(
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                      onTap: onRetry!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small accent pill. A bare [TextButton] read as plain text next to the
/// message it belongs to, so actions get a real, tappable surface.
class AuroraPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const AuroraPill(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: Radii.rPill,
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
          decoration: BoxDecoration(
            borderRadius: Radii.rPill,
            color: AppColors.accent.withValues(alpha: 0.16),
            border: Border.all(
                color: AppColors.accentBright.withValues(alpha: 0.40)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.accentBright),
              const SizedBox(width: 6),
              Text(label,
                  style: text.labelLarge?.copyWith(
                      color: AppColors.accentBright,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Concentric aurora rings, drawn off-centre so the card does not read as a
/// bullseye. Stroke-only and near-invisible by design.
class _RingsPainter extends CustomPainter {
  const _RingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.46);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      paint.color =
          AppColors.accentBright.withValues(alpha: 0.055 - i * 0.011);
      canvas.drawCircle(center, size.height * (0.30 + i * 0.22), paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) => false;
}
