import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/track.dart';
import '../screens/player/now_playing_screen.dart';
import '../state/player_controller.dart';
import 'artwork.dart';
import 'glass.dart';

/// Persistent expandable mini-player. Swipe up / tap to open the full player;
/// swipe down to pause; swipe left / right for next / previous. While paused,
/// dragging it off to the right closes playback. Shows a thin progress line.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  /// Horizontal offset of the card while it is being dragged away.
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );
  double _width = 1;
  bool _dismissing = false;

  static const _dismissFraction = 0.35;
  static const _dismissVelocity = 700.0;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  bool get _canDismiss {
    final s = ref.read(playerControllerProvider);
    return !s.isPlaying && s.hasTrack;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_dismissing || !_canDismiss) return;
    _drag.value = (_drag.value + d.delta.dx).clamp(0.0, _width);
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    if (_dismissing) return;
    final v = d.primaryVelocity ?? 0;
    final controller = ref.read(playerControllerProvider.notifier);
    if (_canDismiss && v >= 0) {
      final far = _drag.value > _width * _dismissFraction;
      if (far || v > _dismissVelocity) {
        _dismissing = true;
        HapticFeedback.mediumImpact();
        await _drag.animateTo(_width,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic);
        await controller.close();
        if (!mounted) return;
        _drag.value = 0;
        _dismissing = false;
        return;
      }
      if (_drag.value > 0) {
        await _drag.animateTo(0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack);
        return;
      }
    }
    if (_drag.value > 0) {
      unawaited(_drag.animateTo(0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack));
    }
    if (v < -120) {
      HapticFeedback.lightImpact();
      controller.next();
    } else if (v > 120 && !_canDismiss) {
      HapticFeedback.lightImpact();
      controller.previous();
    }
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => const NowPlayingScreen(),
        transitionsBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                .animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final track = state.current;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: track == null
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey(track.id),
              padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
              child: GestureDetector(
                onTap: () => _open(context),
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -120) {
                    _open(context);
                  } else if (v > 220) {
                    HapticFeedback.lightImpact();
                    // pause on swipe-down dismiss
                    if (state.isPlaying) {
                      ref.read(playerControllerProvider.notifier).toggle();
                    }
                  }
                },
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _width = constraints.maxWidth;
                    return AnimatedBuilder(
                      animation: _drag,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(_drag.value, 0),
                        child: Opacity(
                          opacity: (1 - _drag.value / _width).clamp(0.0, 1.0),
                          child: child,
                        ),
                      ),
                      child: _card(context, state, track),
                    );
                  },
                ),
              ),
            ),
    );
  }

  Widget _card(BuildContext context, PlayerState state, Track track) {
    final text = Theme.of(context).textTheme;
    return Glass(
      radius: Radii.rLg,
      blur: 22,
      opacity: 0.12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(Sp.sm),
            child: Row(
              children: [
                Hero(
                  tag: 'art_${track.id}',
                  child: Artwork(track: track, size: 46, radius: Radii.rSm),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium),
                      Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium),
                    ],
                  ),
                ),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: state.isLoading && !state.isPlaying
                      ? const Padding(
                          padding: EdgeInsets.all(7),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.accentBright,
                          ),
                        )
                      : IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(state.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          iconSize: 32,
                          color: AppColors.textPrimary,
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            ref
                                .read(playerControllerProvider.notifier)
                                .toggle();
                          },
                        ),
                ),
              ],
            ),
          ),
          _ProgressLine(progress: state.progress, accent: track.accent),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final double progress;
  final Color accent;
  const _ProgressLine({required this.progress, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: progress),
          duration: const Duration(milliseconds: 240),
          builder: (_, value, __) => LinearProgressIndicator(
            value: value,
            minHeight: 3,
            backgroundColor: AppColors.glassStroke,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
      ),
    );
  }
}
