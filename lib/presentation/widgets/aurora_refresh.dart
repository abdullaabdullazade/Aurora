import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

/// Custom pull-to-refresh: a glowing aurora orb that scales + pulses with the
/// overscroll distance, instead of the default Material spinner. Wrap a
/// scrollable that uses BouncingScrollPhysics (so the top can overscroll).
class AuroraRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  final double threshold;

  const AuroraRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.threshold = 110,
  });

  @override
  State<AuroraRefresh> createState() => _AuroraRefreshState();
}

class _AuroraRefreshState extends State<AuroraRefresh>
    with SingleTickerProviderStateMixin {
  double _pull = 0;
  bool _refreshing = false;
  bool _armed = false;
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (_refreshing) return false;
    if (n is ScrollUpdateNotification || n is OverscrollNotification) {
      final m = n.metrics;
      final over = (m.minScrollExtent - m.pixels).clamp(0.0, 240.0);
      if (over != _pull) {
        setState(() => _pull = over);
        if (!_armed && over >= widget.threshold) {
          _armed = true;
          HapticFeedback.mediumImpact();
        }
      }
    }
    if (n is ScrollEndNotification) {
      if (_armed && _pull >= widget.threshold) {
        _trigger();
      } else {
        setState(() => _pull = 0);
      }
      _armed = false;
    }
    return false;
  }

  Future<void> _trigger() async {
    setState(() {
      _refreshing = true;
      _pull = widget.threshold;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
      if (mounted) setState(() => _pull = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (_pull / widget.threshold).clamp(0.0, 1.0);
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: SizedBox(
              height: 90 * t + (_refreshing ? 20 : 0),
              child: Center(
                child: Opacity(
                  opacity: t,
                  child: _Orb(
                    progress: t,
                    spinning: _refreshing,
                    spin: _spin,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  final double progress;
  final bool spinning;
  final Animation<double> spin;
  const _Orb(
      {required this.progress, required this.spinning, required this.spin});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: spin,
      builder: (_, __) {
        final scale = 0.6 + progress * 0.6 + (spinning ? 0.05 : 0);
        return Transform.rotate(
          angle: spinning ? spin.value * 6.28318 : progress * 3.14,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.accentSweep,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(
                        alpha: 0.4 + 0.4 * progress),
                    blurRadius: 30 + 30 * progress,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                spinning ? Icons.graphic_eq_rounded : Icons.arrow_downward_rounded,
                color: Colors.black,
                size: 22,
              ),
            ),
          ),
        );
      },
    );
  }
}
