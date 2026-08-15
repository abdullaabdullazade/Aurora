import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Frosted glass surface: real backdrop blur + translucent fill + hairline
/// stroke. Wrapped in RepaintBoundary so blur doesn't repaint with siblings.
class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final double blur;

  /// White sheen laid over the scrim — the "glass" highlight.
  final double opacity;

  /// Dark base under the sheen. Blur preserves the *color* of whatever is
  /// behind it, so over album art a white-only fill turned the surface into a
  /// bright rainbow smear. The scrim neutralises that before the sheen lands.
  final double scrim;

  final EdgeInsetsGeometry? padding;
  final Border? border;

  const Glass({
    super.key,
    required this.child,
    this.radius = Radii.rLg,
    this.blur = 14,
    this.opacity = 0.08,
    this.scrim = 0.62,
    this.padding,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                Colors.white.withValues(alpha: opacity),
                AppColors.voidBlack.withValues(alpha: scrim),
              ),
              borderRadius: radius,
              border: border ??
                  Border.all(color: AppColors.glassStroke, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Cheap glass look WITHOUT BackdropFilter — for list items, where many real
/// blurs tank scroll performance. Visually close (translucent fill + stroke).
class GlassTile extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final EdgeInsetsGeometry? padding;
  const GlassTile({
    super.key,
    required this.child,
    this.radius = Radii.rLg,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0x14202024),
        borderRadius: radius,
        border: Border.all(color: AppColors.glassStroke, width: 1),
      ),
      child: child,
    );
  }
}
