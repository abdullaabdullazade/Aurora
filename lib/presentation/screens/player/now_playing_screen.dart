import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/track.dart';
import '../../widgets/album_pulse.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass.dart';
import '../../widgets/playback_controls.dart';
import '../../widgets/waveform_seeker.dart';
import '../../state/player_controller.dart';
import '../../state/favorites_controller.dart';
import '../library/add_to_playlist_sheet.dart';
import 'queue_sheet.dart';
import 'lyrics_sheet.dart';
import 'sleep_timer_sheet.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(playerControllerProvider.select((s) => s.error), (_, err) {
      if (err != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.elevated,
            content: Text(err),
          ));
      }
    });

    final state = ref.watch(playerControllerProvider);
    final track = state.current;
    if (track == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final artSize = media.size.width - Sp.xl * 2;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Artwork(
                track: track,
                size: media.size.width * 1.4,
                radius: BorderRadius.zero,
              ),
            ),
          ),
          DecoratedBox(
            decoration:
                BoxDecoration(gradient: AppColors.artVeil(track.accent)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
              child: Column(
                children: [
                  const _TopBar(source: 'From your search'),
                  const Spacer(flex: 3),
                  AlbumPulse(
                    accent: track.accent,
                    active: state.isPlaying,
                    size: artSize,
                    child: Hero(
                      tag: 'art_${track.id}',
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Artwork(
                            track: track,
                            size: artSize,
                            radius: Radii.rXl,
                            glow: true,
                          ),
                          if (state.isLoading)
                            Container(
                              width: artSize,
                              height: artSize,
                              decoration: BoxDecoration(
                                borderRadius: Radii.rXl,
                                color: Colors.black.withValues(alpha: 0.35),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.accentBright),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                  _TitleRow(track: track),
                  const SizedBox(height: Sp.md),
                  WaveformSeeker(
                    progress: state.progress,
                    accent: track.accent,
                    onSeek: (f) =>
                        ref.read(playerControllerProvider.notifier).seek(f),
                  ),
                  const SizedBox(height: Sp.xs),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(Fmt.duration(state.position),
                            style: Theme.of(context).textTheme.labelSmall),
                        Text(Fmt.duration(state.total),
                            style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                  const SizedBox(height: Sp.sm),
                  PlaybackControls(accent: track.accent),
                  const Spacer(flex: 2),
                  _BottomActions(track: track),
                  const SizedBox(height: Sp.md),
                ],
              ),
            ),
          ),
          // Volume drag HUD (right edge).
          const _VolumeDragLayer(),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final String source;
  const _TopBar({required this.source});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final sleeping = ref.watch(
        playerControllerProvider.select((s) => s.sleepRemaining != null));
    return Row(
      children: [
        _RoundIcon(
          icon: Icons.keyboard_arrow_down_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Column(
            children: [
              Text('NOW PLAYING',
                  style: text.labelSmall?.copyWith(
                      letterSpacing: 1.5, color: AppColors.textSecondary)),
              const SizedBox(height: 3),
              Text(source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium),
            ],
          ),
        ),
        _RoundIcon(
          icon: sleeping ? Icons.bedtime_rounded : Icons.bedtime_outlined,
          highlight: sleeping,
          onTap: () => SleepTimerSheet.show(context),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
  const _RoundIcon(
      {required this.icon, required this.onTap, this.highlight = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: highlight
              ? AppColors.accentSoft
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
              color: highlight
                  ? AppColors.accentBright
                  : AppColors.glassStroke),
        ),
        child: Icon(icon,
            size: 22,
            color: highlight
                ? AppColors.accentBright
                : AppColors.textPrimary),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final Track track;
  const _TitleRow({required this.track});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineMedium),
              const SizedBox(height: Sp.xs),
              Text('${track.artist}  ·  ${Fmt.compact(track.plays)} plays',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: Sp.md),
        FavButton(track: track, size: 30),
      ],
    );
  }
}

/// Animated favorite (Liked Songs) toggle with haptic + pop scale.
class FavButton extends ConsumerWidget {
  final Track track;
  final double size;
  const FavButton({super.key, required this.track, this.size = 28});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(favoritesProvider
        .select((list) => list.any((t) => t.id == track.id)));
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ref.read(favoritesProvider.notifier).toggle(track);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(liked),
          color: liked ? AppColors.accentBright : AppColors.textSecondary,
          size: size,
          shadows: liked
              ? [const Shadow(color: AppColors.accentBright, blurRadius: 16)]
              : null,
        ),
      ),
    );
  }
}

/// Right-edge vertical drag → volume, with a thin glass HUD overlay.
class _VolumeDragLayer extends ConsumerStatefulWidget {
  const _VolumeDragLayer();
  @override
  ConsumerState<_VolumeDragLayer> createState() => _VolumeDragLayerState();
}

class _VolumeDragLayerState extends ConsumerState<_VolumeDragLayer> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final vol = ref.watch(playerControllerProvider.select((s) => s.volume));
    return Stack(
      children: [
        // Gesture strip on the right edge, vertically centered.
        Positioned(
          right: 0,
          top: h * 0.22,
          bottom: h * 0.22,
          width: 64,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => setState(() => _show = true),
            onVerticalDragUpdate: (d) {
              ref
                  .read(playerControllerProvider.notifier)
                  .adjustVolume(-d.primaryDelta! / 280);
            },
            onVerticalDragEnd: (_) => setState(() => _show = false),
          ),
        ),
        if (_show)
          Positioned(
            right: Sp.xl,
            top: h * 0.32,
            child: _VolumeHud(value: vol),
          ),
      ],
    );
  }
}

class _VolumeHud extends StatelessWidget {
  final double value;
  const _VolumeHud({required this.value});
  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Radii.rPill,
      blur: 24,
      opacity: 0.14,
      padding: const EdgeInsets.symmetric(vertical: Sp.md, horizontal: Sp.sm),
      child: Column(
        children: [
          Icon(
            value <= 0.001
                ? Icons.volume_off_rounded
                : value < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            color: AppColors.accentBright,
            size: 20,
          ),
          const SizedBox(height: Sp.sm),
          SizedBox(
            height: 120,
            width: 6,
            child: RotatedBox(
              quarterTurns: 3,
              child: ClipRRect(
                borderRadius: Radii.rPill,
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: AppColors.glassStroke,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.accentBright),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Text('${(value * 100).round()}',
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final Track track;
  const _BottomActions({required this.track});

  void _sheet(BuildContext context, Widget child) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => child,
      );

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: Radii.rPill,
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Action(
            icon: Icons.lyrics_outlined,
            label: 'Lyrics',
            onTap: () => _sheet(context, const LyricsSheet()),
          ),
          _Action(
            icon: Icons.playlist_add_rounded,
            label: 'Add',
            onTap: () => AddToPlaylistSheet.show(context, track),
          ),
          _Action(
            icon: Icons.queue_music_rounded,
            label: 'Queue',
            onTap: () => _sheet(context, const QueueSheet()),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: AppColors.textPrimary),
      label: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: AppColors.textPrimary)),
    );
  }
}
