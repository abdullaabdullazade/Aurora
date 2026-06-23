import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../screens/player/now_playing_screen.dart';
import '../state/player_controller.dart';
import 'artwork.dart';
import 'glass.dart';

/// Persistent expandable mini-player. Swipe up / tap to open the full player;
/// swipe down to dismiss. Shows a thin live progress line.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final track = state.current;
    final text = Theme.of(context).textTheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
            .animate(anim),
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
                child: Glass(
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
                              child: Artwork(
                                  track: track, size: 46, radius: Radii.rSm),
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
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded),
                              iconSize: 26,
                              visualDensity: VisualDensity.compact,
                              color: AppColors.textSecondary,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .previous();
                              },
                            ),
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: state.isLoading
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
                                            .read(playerControllerProvider
                                                .notifier)
                                            .toggle();
                                      },
                                    ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded),
                              iconSize: 26,
                              visualDensity: VisualDensity.compact,
                              color: AppColors.textSecondary,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .next();
                              },
                            ),
                          ],
                        ),
                      ),
                      _ProgressLine(
                          progress: state.progress, accent: track.accent),
                    ],
                  ),
                ),
              ),
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
