import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Tiny animated equalizer bars shown on the track that's currently playing.
/// Bars freeze (flat) when [playing] is false.
class NowPlayingBars extends StatefulWidget {
  final Color color;
  final bool playing;
  final double size;
  const NowPlayingBars({
    super.key,
    required this.color,
    this.playing = true,
    this.size = 18,
  });

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _BarsPainter(_c.value, widget.color, widget.playing),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final double t;
  final Color color;
  final bool playing;
  _BarsPainter(this.t, this.color, this.playing);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 4;
    final slot = size.width / n;
    final w = slot * 0.55;
    final paint = Paint()
      ..color = color
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final phase = t * 2 * math.pi + i * 1.3;
      final amp = playing ? (0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase))) : 0.3;
      final h = size.height * amp;
      final x = i * slot + slot / 2;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter o) =>
      o.t != t || o.color != color || o.playing != playing;
}
