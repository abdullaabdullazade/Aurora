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
import '../../widgets/waveform_seeker.dart';
import '../../state/player_controller.dart';
import '../../state/favorites_controller.dart';
import '../../state/output_controller.dart';
import '../artist/artist_detail_screen.dart';
import '../library/add_to_playlist_sheet.dart';
import '../library/track_context_sheet.dart';
import 'queue_sheet.dart';
import 'lyrics_sheet.dart';
import 'sleep_timer_sheet.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  // Slow vertical bob for the floating-artwork effect.
  late final AnimationController _float = AnimationController(
      vsync: this, duration: const Duration(seconds: 5))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    final artSize = (media.size.width * 0.74).clamp(220.0, 360.0);

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layered blurred-artwork background + dark gradient veil.
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Artwork(
                track: track,
                size: media.size.width * 1.5,
                radius: BorderRadius.zero,
              ),
            ),
          ),
          DecoratedBox(
            decoration:
                BoxDecoration(gradient: AppColors.artVeil(track.accent)),
          ),
          // Extra bottom darkening for control legibility.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x99000000)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
              child: Column(
                children: [
                  const _TopBar(source: 'From your search'),
                  const SizedBox(height: Sp.sm),
                  const Row(
                    children: [
                      _SpeedChip(),
                      Spacer(),
                      _OutputChip(),
                    ],
                  ),
                  // Artwork takes the flexible upper space, centered + floating.
                  Expanded(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _float,
                        builder: (_, child) => Transform.translate(
                          offset: Offset(0, (_float.value - 0.5) * 14),
                          child: child,
                        ),
                        child: AlbumPulse(
                          accent: track.accent,
                          active: state.isPlaying,
                          size: artSize,
                          child: _FloatingArt(
                            track: track,
                            size: artSize,
                            loading: state.isLoading,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ---- Bottom cluster, exact spacing rhythm ----
                  const SizedBox(height: 24), // artwork -> title
                  _SongInfo(track: track),
                  const SizedBox(height: 20), // title -> progress
                  WaveformSeeker(
                    progress: state.progress,
                    position: state.position,
                    total: state.total,
                    accent: track.accent,
                    onSeek: (f) =>
                        ref.read(playerControllerProvider.notifier).seek(f),
                  ),
                  const SizedBox(height: 28), // progress -> controls
                  const _Controls(),
                  const SizedBox(height: 32), // controls -> bottom bar
                  const _BottomBar(),
                  const SizedBox(height: Sp.sm),
                ],
              ),
            ),
          ),
          const _VolumeDragLayer(),
        ],
      ),
    );
  }
}

class _FloatingArt extends StatelessWidget {
  final Track track;
  final double size;
  final bool loading;
  const _FloatingArt(
      {required this.track, required this.size, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'art_${track.id}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            // soft ambient shadow + artwork-colored glow
            const BoxShadow(
                color: Color(0x66000000), blurRadius: 44, offset: Offset(0, 24)),
            BoxShadow(
              color: track.accent.withValues(alpha: 0.5),
              blurRadius: 70,
              spreadRadius: -14,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Artwork(
              track: track,
              size: size,
              radius: BorderRadius.circular(32),
            ),
            if (loading)
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  color: Colors.black.withValues(alpha: 0.32),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accentBright),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpeedChip extends ConsumerWidget {
  const _SpeedChip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playerControllerProvider.select((s) => s.speed));
    final label = speed == speed.roundToDouble()
        ? '${speed.toInt()}x'
        : '${speed}x';
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(playerControllerProvider.notifier).cycleSpeed();
      },
      child: Glass(
        radius: Radii.rPill,
        blur: 18,
        opacity: 0.10,
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.speed_rounded,
                size: 14, color: AppColors.accentBright),
            const SizedBox(width: Sp.sm),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _OutputChip extends ConsumerWidget {
  const _OutputChip();

  void _sheet(BuildContext context, OutputDevice d) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Glass(
        radius: const BorderRadius.vertical(top: Radii.xl),
        blur: 30,
        opacity: 0.16,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: Sp.md),
              Container(
                  width: 44,
                  height: 4,
                  decoration: const BoxDecoration(
                      color: AppColors.glassStroke,
                      borderRadius: Radii.rPill)),
              Padding(
                padding: const EdgeInsets.all(Sp.lg),
                child: Text('Audio output',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              ListTile(
                leading: Icon(_iconFor(d.kind),
                    color: AppColors.accentBright),
                title: Text('Playing on ${d.label}'),
                trailing:
                    const Icon(Icons.check_rounded, color: AppColors.accentBright),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.lg),
                child: Text(
                  'Connect headphones or Bluetooth and audio switches '
                  'automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(OutputKind k) => switch (k) {
        OutputKind.bluetooth => Icons.bluetooth_audio_rounded,
        OutputKind.headphones => Icons.headphones_rounded,
        OutputKind.speaker => Icons.speaker_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(outputDeviceProvider).valueOrNull ??
        const OutputDevice(OutputKind.speaker, 'Device Speakers');
    return GestureDetector(
      onTap: () => _sheet(context, d),
      child: Glass(
        radius: Radii.rPill,
        blur: 18,
        opacity: 0.10,
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(d.kind), size: 14, color: AppColors.accentBright),
            const SizedBox(width: Sp.sm),
            Text('Output: ${d.label}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _SongInfo extends StatelessWidget {
  final Track track;
  const _SongInfo({required this.track});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  height: 1.12,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ArtistDetailScreen(
                      artist: track.artist,
                      accent: track.accent,
                      channelUrl: track.channelUrl),
                )),
                child: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${Fmt.compact(track.plays)} plays',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Sp.md),
        FavButton(track: track, size: 30),
      ],
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
                      letterSpacing: 1.6, color: AppColors.textSecondary)),
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
        const SizedBox(width: Sp.sm),
        _RoundIcon(
          icon: Icons.more_horiz_rounded,
          onTap: () {
            final t = ref.read(playerControllerProvider).current;
            if (t != null) TrackContextSheet.show(context, t);
          },
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

/// Favorite toggle (animated + haptic).
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

/// Transport row centered on a glassy 60px play button.
class _Controls extends ConsumerWidget {
  const _Controls();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final accent = state.current?.accent ?? AppColors.accent;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _MiniBtn(
          icon: Icons.shuffle_rounded,
          active: state.shuffle,
          accent: accent,
          onTap: ctrl.toggleShuffle,
        ),
        _PressBtn(
          onTap: () {
            HapticFeedback.lightImpact();
            ctrl.previous();
          },
          child: const Icon(Icons.skip_previous_rounded,
              size: 42, color: Colors.white),
        ),
        _PlayButton(
          isPlaying: state.isPlaying,
          loading: state.isLoading,
          accent: accent,
          onTap: () {
            HapticFeedback.mediumImpact();
            ctrl.toggle();
          },
        ),
        _PressBtn(
          onTap: () {
            HapticFeedback.lightImpact();
            ctrl.next();
          },
          child: const Icon(Icons.skip_next_rounded,
              size: 42, color: Colors.white),
        ),
        _MiniBtn(
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

class _PlayButton extends StatefulWidget {
  final bool isPlaying;
  final bool loading;
  final Color accent;
  final VoidCallback onTap;
  const _PlayButton({
    required this.isPlaying,
    required this.loading,
    required this.accent,
    required this.onTap,
  });
  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  double _s = 1;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _s = 0.92),
      onTapCancel: () => setState(() => _s = 1),
      onTapUp: (_) => setState(() => _s = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _s,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.accentSweep,
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.55),
                blurRadius: 28,
                spreadRadius: -2,
              ),
            ],
          ),
          child: widget.loading
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                      strokeWidth: 2.6, color: Colors.black),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(
                    widget.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    key: ValueKey(widget.isPlaying),
                    color: Colors.black,
                    size: 32,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PressBtn extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressBtn({required this.child, required this.onTap});
  @override
  State<_PressBtn> createState() => _PressBtnState();
}

class _PressBtnState extends State<_PressBtn> {
  double _s = 1;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _s = 0.85),
      onTapCancel: () => setState(() => _s = 1),
      onTapUp: (_) => setState(() => _s = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _s,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  const _MiniBtn(
      {required this.icon,
      required this.active,
      required this.accent,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 24,
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

/// Floating glass action bar (Lyrics / Add / Queue), Apple-Music style.
class _BottomBar extends ConsumerWidget {
  const _BottomBar();

  void _sheet(BuildContext context, Widget child) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => child,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerControllerProvider).current;
    if (track == null) return const SizedBox.shrink();
    return Glass(
      radius: const BorderRadius.all(Radius.circular(24)),
      blur: 26,
      opacity: 0.12,
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Action(
              icon: Icons.lyrics_outlined,
              label: 'Lyrics',
              onTap: () => _sheet(context, const LyricsSheet())),
          _Action(
              icon: Icons.playlist_add_rounded,
              label: 'Add',
              onTap: () => AddToPlaylistSheet.show(context, track)),
          _Action(
              icon: Icons.queue_music_rounded,
              label: 'Queue',
              onTap: () => _sheet(context, const QueueSheet())),
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
    return InkWell(
      borderRadius: Radii.rMd,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: AppColors.textPrimary),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ],
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
        Positioned(
          right: 0,
          top: h * 0.24,
          bottom: h * 0.30,
          width: 56,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => setState(() => _show = true),
            onVerticalDragUpdate: (d) => ref
                .read(playerControllerProvider.notifier)
                .adjustVolume(-d.primaryDelta! / 280),
            onVerticalDragEnd: (_) => setState(() => _show = false),
          ),
        ),
        if (_show)
          Positioned(
            right: Sp.xl,
            top: h * 0.34,
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
