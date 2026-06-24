import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Animated radial ambient backdrop. Two soft color blobs drift slowly,
/// blurred into the void black. Cheap (single CustomPaint) and gorgeous.
class AmbientBackground extends StatefulWidget {
  final Color seed;
  final Widget child;
  const AmbientBackground({
    super.key,
    required this.child,
    this.seed = AppColors.accent,
  });

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _AmbientPainter(_c.value, widget.seed, dark),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final double t;
  final Color seed;
  final bool dark;
  _AmbientPainter(this.t, this.seed, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect, Paint()..color = dark ? AppColors.voidBlack : const Color(0xFFF3F3F6));

    final a1 = dark ? 0.30 : 0.16;
    final a2 = dark ? 0.12 : 0.08;
    _blob(
      canvas,
      Offset(size.width * (0.2 + 0.15 * t), size.height * 0.18),
      size.width * 0.7,
      seed.withValues(alpha: a1),
    );
    _blob(
      canvas,
      Offset(size.width * (0.85 - 0.2 * t), size.height * (0.7 + 0.05 * t)),
      size.width * 0.55,
      AppColors.accent.withValues(alpha: a2),
    );
  }

  void _blob(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
          .createShader(Rect.fromCircle(center: center, radius: radius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.t != t || old.seed != seed || old.dark != dark;
}
