import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../state/player_controller.dart';

/// Oversized tactile transport row with a glowing play/pause core.
class PlaybackControls extends ConsumerWidget {
  final Color accent;
  const PlaybackControls({super.key, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SmallBtn(
          icon: Icons.shuffle_rounded,
          active: state.shuffle,
          accent: accent,
          onTap: ctrl.toggleShuffle,
        ),
        _SmallBtn(
          icon: Icons.skip_previous_rounded,
          size: 38,
          onTap: () {
            HapticFeedback.lightImpact();
            ctrl.previous();
          },
        ),
        _PlayCore(
          isPlaying: state.isPlaying,
          accent: accent,
          onTap: () {
            HapticFeedback.mediumImpact();
            ctrl.toggle();
          },
        ),
        _SmallBtn(
          icon: Icons.skip_next_rounded,
          size: 38,
          onTap: () {
            HapticFeedback.lightImpact();
            ctrl.next();
          },
        ),
        _SmallBtn(
          icon: switch (state.repeat) {
            LoopMode.one => Icons.repeat_one_rounded,
            _ => Icons.repeat_rounded,
          },
          active: state.repeat != LoopMode.off,
          accent: accent,
          onTap: ctrl.cycleRepeat,
        ),
      ],
    );
  }
}

class _PlayCore extends StatelessWidget {
  final bool isPlaying;
  final Color accent;
  final VoidCallback onTap;
  const _PlayCore(
      {required this.isPlaying, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.accentSweep,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.55),
              blurRadius: 34,
              spreadRadius: -2,
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            key: ValueKey(isPlaying),
            color: Colors.black,
            size: 40,
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final double size;
  final Color accent;
  const _SmallBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.size = 26,
    this.accent = AppColors.accentBright,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: size,
      icon: Icon(
        icon,
        color: active ? accent : AppColors.textSecondary,
        shadows: active
            ? [Shadow(color: accent.withValues(alpha: 0.8), blurRadius: 12)]
            : null,
      ),
    );
  }
}
