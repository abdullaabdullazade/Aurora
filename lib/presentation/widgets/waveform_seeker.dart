import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

/// Audio-style waveform that doubles as the seek bar. Bars fill with the accent
/// up to [progress]; scrubbing stretches bars near the finger (elastic) and
/// fires a haptic tick as you cross each bar.
class WaveformSeeker extends StatefulWidget {
  final double progress; // 0..1
  final Color accent;
  final ValueChanged<double> onSeek;
  final ValueChanged<double>? onScrub; // live fraction while dragging
  final int bars;
  final double height;

  const WaveformSeeker({
    super.key,
    required this.progress,
    required this.accent,
    required this.onSeek,
    this.onScrub,
    this.bars = 56,
    this.height = 48,
  });

  @override
  State<WaveformSeeker> createState() => _WaveformSeekerState();
}

class _WaveformSeekerState extends State<WaveformSeeker> {
  double? _drag; // fraction while dragging
  int _lastBar = -1;

  // Deterministic pseudo-waveform amplitudes (stable across rebuilds).
  late final List<double> _amps = List.generate(widget.bars, (i) {
    final r = math.sin(i * 0.7) * 0.5 + math.sin(i * 1.7) * 0.3;
    return 0.35 + (r.abs() * 0.65);
  });

  void _update(double dx, double width) {
    final f = (dx / width).clamp(0.0, 1.0);
    final bar = (f * widget.bars).floor();
    if (bar != _lastBar) {
      HapticFeedback.selectionClick();
      _lastBar = bar;
    }
    setState(() => _drag = f);
    widget.onScrub?.call(f);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _update(d.localPosition.dx, width),
        onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, width),
        onHorizontalDragEnd: (_) {
          if (_drag != null) widget.onSeek(_drag!);
          setState(() => _drag = null);
          _lastBar = -1;
        },
        onTapDown: (d) => _update(d.localPosition.dx, width),
        onTapUp: (_) {
          if (_drag != null) widget.onSeek(_drag!);
          setState(() => _drag = null);
        },
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _WavePainter(
              amps: _amps,
              progress: _drag ?? widget.progress,
              accent: widget.accent,
              dragging: _drag != null,
            ),
          ),
        ),
      );
    });
  }
}

class _WavePainter extends CustomPainter {
  final List<double> amps;
  final double progress;
  final Color accent;
  final bool dragging;
  _WavePainter({
    required this.amps,
    required this.progress,
    required this.accent,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = amps.length;
    final slot = size.width / n;
    final barW = slot * 0.5;
    final mid = size.height / 2;
    final headBar = (progress * n);

    for (var i = 0; i < n; i++) {
      final filled = i <= headBar;
      // Elastic bump near the scrub head while dragging.
      var amp = amps[i];
      if (dragging) {
        final d = (i - headBar).abs();
        if (d < 3) amp *= 1.0 + (3 - d) / 3 * 0.6;
      }
      final h = (size.height * 0.9) * amp.clamp(0.0, 1.0);
      final x = i * slot + slot / 2;
      final paint = Paint()
        ..color = filled
            ? accent
            : AppColors.textPrimary.withValues(alpha: 0.14)
        ..strokeWidth = barW
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }

    // Glow head.
    final hx = (progress * size.width).clamp(0.0, size.width);
    canvas.drawCircle(
      Offset(hx, mid),
      dragging ? 7 : 5,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(_WavePainter o) =>
      o.progress != progress || o.accent != accent || o.dragging != dragging;
}
