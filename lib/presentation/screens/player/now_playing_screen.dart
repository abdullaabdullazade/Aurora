import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/track.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass.dart';
import '../../widgets/playback_controls.dart';
import '../../state/player_controller.dart';
import '../../state/favorites_controller.dart';
import '../library/add_to_playlist_sheet.dart';
import 'queue_sheet.dart';
import 'lyrics_sheet.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface playback errors as a snackbar.
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
          // Blurred album-art ambient backdrop.
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
                  _TopBar(source: 'From your search'),
                  const Spacer(flex: 3),
                  // Artwork with loading overlay.
                  Hero(
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
                  const Spacer(flex: 3),
                  _TitleRow(track: track),
                  const SizedBox(height: Sp.lg),
                  _Seeker(
                    progress: state.progress,
                    position: state.position,
                    total: state.total,
                    accent: track.accent,
                    onSeek: (f) =>
                        ref.read(playerControllerProvider.notifier).seek(f),
                  ),
                  const SizedBox(height: Sp.md),
                  PlaybackControls(accent: track.accent),
                  const Spacer(flex: 2),
                  _BottomActions(track: track),
                  const SizedBox(height: Sp.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String source;
  const _TopBar({required this.source});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
                  style: text.labelSmall
                      ?.copyWith(letterSpacing: 1.5, color: AppColors.textSecondary)),
              const SizedBox(height: 3),
              Text(source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium),
            ],
          ),
        ),
        _RoundIcon(icon: Icons.more_horiz_rounded, onTap: () {}),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: AppColors.glassStroke),
        ),
        child: Icon(icon, size: 24, color: AppColors.textPrimary),
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
              ? [
                  const Shadow(
                      color: AppColors.accentBright, blurRadius: 16),
                ]
              : null,
        ),
      ),
    );
  }
}

/// Custom seeker: thin track, scrubbing emits selection haptics.
class _Seeker extends StatefulWidget {
  final double progress;
  final Duration position;
  final Duration total;
  final Color accent;
  final ValueChanged<double> onSeek;
  const _Seeker({
    required this.progress,
    required this.position,
    required this.total,
    required this.accent,
    required this.onSeek,
  });

  @override
  State<_Seeker> createState() => _SeekerState();
}

class _SeekerState extends State<_Seeker> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final value = _drag ?? widget.progress;
    final shown = _drag != null ? widget.total * _drag! : widget.position;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 5,
            activeTrackColor: widget.accent,
            thumbColor: Colors.white,
            overlayColor: widget.accent.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChangeStart: (_) => HapticFeedback.selectionClick(),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _drag = v);
            },
            onChangeEnd: (v) {
              widget.onSeek(v);
              setState(() => _drag = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(Fmt.duration(shown), style: text.labelSmall),
              Text(Fmt.duration(widget.total), style: text.labelSmall),
            ],
          ),
        ),
      ],
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
