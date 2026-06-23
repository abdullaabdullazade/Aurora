import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass.dart';
import '../../widgets/playback_controls.dart';
import '../../state/player_controller.dart';
import 'queue_sheet.dart';
import 'lyrics_sheet.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final track = state.current;
    if (track == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- Blurred album-art ambient backdrop ---
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
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
          // --- Foreground ---
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
              child: Column(
                children: [
                  _TopBar(subtitle: 'Playing from Aurora'),
                  const Spacer(flex: 2),
                  Hero(
                    tag: 'art_${track.id}',
                    child: Artwork(
                      track: track,
                      size: media.size.width - Sp.xl * 2,
                      radius: Radii.rXl,
                      glow: true,
                    ),
                  ),
                  const Spacer(flex: 2),
                  // Title + artist + like
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.headlineMedium),
                            const SizedBox(height: Sp.xs),
                            Text(track.artist, style: text.bodyMedium),
                          ],
                        ),
                      ),
                      const Icon(Icons.favorite_border_rounded,
                          color: AppColors.accentBright, size: 28),
                    ],
                  ),
                  const SizedBox(height: Sp.lg),
                  _Seeker(
                    progress: state.progress,
                    position: state.position,
                    total: state.total,
                    accent: track.accent,
                    onSeek: (f) =>
                        ref.read(playerControllerProvider.notifier).seek(f),
                  ),
                  const SizedBox(height: Sp.sm),
                  PlaybackControls(accent: track.accent),
                  const Spacer(flex: 1),
                  const _BottomActions(),
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
  final String subtitle;
  const _TopBar({required this.subtitle});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
        ),
        Expanded(
          child: Column(
            children: [
              Text('NOW PLAYING', style: text.labelSmall),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: text.titleMedium, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.more_horiz_rounded, size: 28),
        ),
      ],
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
    final shown = _drag != null
        ? widget.total * _drag!
        : widget.position;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
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
  const _BottomActions();

  void _sheet(BuildContext context, Widget child) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => child,
    );
  }

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
            icon: Icons.arrow_circle_down_rounded,
            label: 'Download',
            onTap: () => HapticFeedback.mediumImpact(),
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
