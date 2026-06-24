import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight particle/glow system rendered behind the album art. Particles
/// orbit and a soft ring breathes; speed + opacity rise while [active].
/// Not a real FFT visualizer — a tasteful, cheap approximation.
class AlbumPulse extends StatefulWidget {
  final Color accent;
  final bool active;
  final double size; // matches the art box
  final Widget child;

  const AlbumPulse({
    super.key,
    required this.accent,
    required this.active,
    required this.size,
    required this.child,
  });

  @override
  State<AlbumPulse> createState() => _AlbumPulseState();
}

class _AlbumPulseState extends State<AlbumPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

  static const _count = 14;
  late final List<_P> _particles = List.generate(_count, (i) {
    final a = i / _count * math.pi * 2;
    return _P(angle: a, radius: 0.52 + (i % 4) * 0.05, speed: 0.6 + (i % 5) * 0.18, sz: 1.5 + (i % 3) * 1.2);
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * 1.5; // canvas larger than art for overflow glow
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: OverflowBox(
              maxWidth: box,
              maxHeight: box,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => CustomPaint(
                    size: Size(box, box),
                    painter: _PulsePainter(
                      t: _c.value,
                      accent: widget.accent,
                      active: widget.active,
                      particles: _particles,
                    ),
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _P {
  final double angle;
  final double radius;
  final double speed;
  final double sz;
  const _P({
    required this.angle,
    required this.radius,
    required this.speed,
    required this.sz,
  });
}

class _PulsePainter extends CustomPainter {
  final double t;
  final Color accent;
  final bool active;
  final List<_P> particles;
  _PulsePainter({
    required this.t,
    required this.accent,
    required this.active,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.width / 2;
    final intensity = active ? 1.0 : 0.35;
    final breathe = 0.5 + 0.5 * math.sin(t * math.pi * 2);

    // Breathing ring just outside the art.
    final ringR = base * (0.70 + breathe * 0.04 * intensity);
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: 0.10 + 0.18 * intensity * breathe),
    );

    // Orbiting particles.
    for (final p in particles) {
      final ang = p.angle + t * math.pi * 2 * p.speed * (active ? 1 : 0.4);
      final r = base * p.radius * (1 + 0.03 * math.sin(t * math.pi * 2 + p.angle));
      final pos = center + Offset(math.cos(ang), math.sin(ang)) * r;
      final op = (0.12 + 0.5 * intensity) *
          (0.5 + 0.5 * math.sin(t * math.pi * 2 * p.speed + p.angle));
      canvas.drawCircle(
        pos,
        p.sz * (active ? 1.0 : 0.7),
        Paint()..color = accent.withValues(alpha: op.clamp(0.0, 0.7)),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter o) =>
      o.t != t || o.accent != accent || o.active != active;
}
