import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/dynamic_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/track.dart';
import '../../widgets/album_pulse.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass.dart';
import '../../widgets/waveform_seeker.dart';
import '../../state/player_controller.dart';
import '../../state/favorites_controller.dart';
import '../../state/output_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import '../artist/artist_detail_screen.dart';
import '../library/add_to_playlist_sheet.dart';
import '../library/track_context_sheet.dart';
import 'queue_sheet.dart';
import 'lyrics_sheet.dart';

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

    // Watch ONLY the current track here — position updates (4×/sec) must not
    // rebuild the heavy blurred background. Dynamic bits use their own Consumer.
    final track = ref.watch(playerControllerProvider.select((s) => s.current));
    if (track == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final artSize = (media.size.width * 0.74).clamp(220.0, 360.0);

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _SwipeDownDismiss(
            onDismiss: () => Navigator.of(context).maybePop(),
            child: Stack(
              fit: StackFit.expand,
              children: [
          // Layered blurred-artwork background + dark gradient veil.
          // The blur is held at low opacity on purpose: it is texture, not a
          // background. At full strength a bright cover pushes the composite
          // luminance up far enough to sink the secondary labels drawn on it.
          RepaintBoundary(
            child: Opacity(
              opacity: 0.35,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                // Square, sized off the LONGEST edge. Sizing it off the width
                // left the bottom of a tall screen outside the artwork, and
                // that edge showed up as a hard horizontal seam across the
                // controls where the tint stopped.
                child: Artwork(
                  track: track,
                  size: media.size.longestSide * 1.2,
                  radius: BorderRadius.zero,
                ),
              ),
            ),
          ),
          // Neutral until the palette lands, then cross-faded into the
          // artwork's hue. Painting the id-hash accent immediately put a
          // teal wash under a blue cover while the track was still loading.
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: AppColors.artVeil(
                  track.paletteReady ? track.accent : AppColors.base),
            ),
          ),
          // A light extra scrim under the controls. It used to reach 60% black
          // from mid-screen down, which read as a separate black panel bolted
          // under the tinted half rather than one continuous wash.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x33000000)],
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
                        // Only rebuilds on play/loading change, not per tick.
                        child: Consumer(builder: (_, r, __) {
                          final playing = r.watch(playerControllerProvider
                              .select((s) => s.isPlaying));
                          final loading = r.watch(playerControllerProvider
                              .select((s) => s.isLoading));
                          return AlbumPulse(
                            accent: track.accent,
                            active: playing,
                            size: artSize,
                            child: _FloatingArt(
                                track: track, size: artSize, loading: loading),
                          );
                        }),
                      ),
                    ),
                  ),
                  // ---- Bottom cluster, exact spacing rhythm ----
                  const SizedBox(height: 24), // artwork -> title
                  _SongInfo(track: track),
                  const SizedBox(height: 20), // title -> progress
                  // Position-dependent: isolated so only the seek bar repaints.
                  Consumer(builder: (_, r, __) {
                    final s = r.watch(playerControllerProvider);
                    return WaveformSeeker(
                      progress: s.progress,
                      position: s.position,
                      total: s.total,
                      accent: track.accent,
                      onSeek: (f) =>
                          ref.read(playerControllerProvider.notifier).seek(f),
                    );
                  }),
                  const SizedBox(height: 28), // progress -> controls
                  const _Controls(),
                  const SizedBox(height: 32), // controls -> bottom bar
                  const _BottomBar(),
                  const SizedBox(height: Sp.sm),
                ],
              ),
            ),
          ),
              ],
            ),
          ),
          const _VolumeDragLayer(),
        ],
      ),
    );
  }
}

/// Drag down to close — same as the top-bar chevron (`Navigator.maybePop`).
class _SwipeDownDismiss extends StatefulWidget {
  const _SwipeDownDismiss({required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  State<_SwipeDownDismiss> createState() => _SwipeDownDismissState();
}

class _SwipeDownDismissState extends State<_SwipeDownDismiss>
    with SingleTickerProviderStateMixin {
  static const _dismissDistance = 120.0;
  static const _dismissVelocity = 400.0;

  double _offset = 0;
  late final AnimationController _snap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  Animation<double>? _snapAnimation;

  @override
  void initState() {
    super.initState();
    _snap.addListener(() {
      final anim = _snapAnimation;
      if (anim != null) setState(() => _offset = anim.value);
    });
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _snap.stop();
    _snapAnimation = null;
    setState(() {
      _offset = (_offset + details.primaryDelta!).clamp(0.0, double.infinity);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_offset > _dismissDistance || velocity > _dismissVelocity) {
      HapticFeedback.lightImpact();
      widget.onDismiss();
      return;
    }
    _snapAnimation = Tween<double>(begin: _offset, end: 0).animate(
      CurvedAnimation(parent: _snap, curve: Curves.easeOut),
    );
    _snap.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(0, _offset),
        child: widget.child,
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

  void _sheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _OutputSheet(),
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
      onTap: () => _sheet(context),
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

class _OutputSheet extends ConsumerStatefulWidget {
  const _OutputSheet();

  @override
  ConsumerState<_OutputSheet> createState() => _OutputSheetState();
}

class _OutputSheetState extends ConsumerState<_OutputSheet> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await Permission.bluetoothConnect.request();
      } catch (_) {}
      if (mounted) ref.invalidate(audioOutputsProvider);
    });
  }

  Future<void> _select(OutputDevice d) async {
    if (_busy) return;
    final id = d.id;
    if (id == null || id.isEmpty) {
      _closeWithFallback();
      return;
    }
    setState(() => _busy = true);
    final ok = await selectAudioOutput(id);
    if (!mounted) return;
    if (ok) {
      // Let system A2DP settle, then refresh chip from getDevices.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      try {
        await ref
            .read(playerControllerProvider.notifier)
            .republishNowPlayingMetadata();
      } catch (_) {}
      if (!mounted) return;
      ref.invalidate(audioOutputsProvider);
      ref.invalidate(outputDeviceProvider);
      setState(() => _busy = false);
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = false);
    ref.invalidate(audioOutputsProvider);
    _closeWithFallback();
  }

  /// Android 13+ reserves A2DP connect/disconnect for system apps, so the
  /// in-app switch often fails there; hand the user the system screen. The
  /// sheet is closed first: a SnackBar would render underneath it.
  void _closeWithFallback() {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not switch output from the app'),
        action: SnackBarAction(
          label: 'Bluetooth settings',
          onPressed: openOutputPicker,
        ),
      ),
    );
  }

  IconData _iconFor(OutputKind k) => switch (k) {
        OutputKind.bluetooth => Icons.bluetooth_audio_rounded,
        OutputKind.headphones => Icons.headphones_rounded,
        OutputKind.speaker => Icons.smartphone_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final outputs = ref.watch(audioOutputsProvider);

    return Glass(
      radius: const BorderRadius.vertical(top: Radii.xl),
      blur: 30,
      opacity: 0.16,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: Sp.md),
              Container(
                width: 44,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.glassStroke,
                  borderRadius: Radii.rPill,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Audio output',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_busy || outputs.isLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: () =>
                            ref.invalidate(audioOutputsProvider),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: outputs.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(Sp.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => Padding(
                    padding: const EdgeInsets.all(Sp.lg),
                    child: Text(
                      'Could not list devices',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(Sp.lg),
                        child: Text(
                          'No outputs found',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final d = list[i];
                        return ListTile(
                          leading: Icon(
                            _iconFor(d.kind),
                            color: AppColors.accentBright,
                          ),
                          title: Text(d.label),
                          subtitle: Text(switch (d.kind) {
                            OutputKind.speaker => 'This phone',
                            OutputKind.headphones => 'Wired / USB',
                            OutputKind.bluetooth => 'Bluetooth',
                          }),
                          trailing: d.isActive
                              ? const Icon(Icons.check_rounded,
                                  color: AppColors.accentBright)
                              : null,
                          onTap: () => _select(d),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.lg),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      openOutputPicker();
                    },
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('More (system)'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongInfo extends StatelessWidget {
  final Track track;
  const _SongInfo({required this.track});

  static const _titleStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w600,
    height: 1.12,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _MarqueeTitle(
                text: track.title,
                style: _titleStyle,
              ),
            ),
            const SizedBox(width: Sp.md),
            FavButton(track: track, size: 30),
          ],
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
    );
  }
}

/// Spotify-style title: continuous loop scroll when text overflows.
class _MarqueeTitle extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeTitle({required this.text, required this.style});

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _textWidth = 0;
  double _viewport = 0;

  static const _startPause = Duration(milliseconds: 1500);
  static const _gap = 48.0;
  static const _pxPerSec = 40.0;

  bool get _needsScroll => _textWidth > _viewport && _viewport > 0;

  double get _cycle => _textWidth + _gap;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _MarqueeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _ctrl.stop();
      _ctrl.value = 0;
      setState(() {
        _textWidth = 0;
        _viewport = 0;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _startLoop() async {
    if (!mounted || !_needsScroll) return;
    await Future.delayed(_startPause);
    if (!mounted || !_needsScroll) return;
    final ms = (_cycle / _pxPerSec * 1000).clamp(2000, 20000).round();
    _ctrl.duration = Duration(milliseconds: ms);
    _ctrl.repeat();
  }

  void _measure(double maxWidth) {
    if (maxWidth <= 0) return;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final tw = painter.width;
    if ((tw - _textWidth).abs() < 0.5 && (maxWidth - _viewport).abs() < 0.5) {
      return;
    }
    final wasScrolling = _needsScroll;
    setState(() {
      _textWidth = tw;
      _viewport = maxWidth;
    });
    if (!_needsScroll) {
      _ctrl.stop();
      _ctrl.value = 0;
    } else if (!wasScrolling || !_ctrl.isAnimating) {
      _ctrl.value = 0;
      _startLoop();
    } else {
      // Keep looping; refresh duration if cycle length changed.
      final ms = (_cycle / _pxPerSec * 1000).clamp(2000, 20000).round();
      _ctrl.duration = Duration(milliseconds: ms);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _measure(constraints.maxWidth);
        });

        Widget label() => Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: widget.style,
            );

        if (!_needsScroll) {
          return label();
        }

        return ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              colors: [
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.88, 1.0],
            ).createShader(rect),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => Transform.translate(
                offset: Offset(-_cycle * _ctrl.value, 0),
                child: child,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  label(),
                  const SizedBox(width: _gap),
                  label(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends ConsumerWidget {
  final String source;
  const _TopBar({required this.source});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        const SizedBox(width: 42),
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
        GestureDetector(
          onTap: () {
            final t = ref.read(playerControllerProvider).current;
            if (t != null) {
              TrackContextSheet.show(context, t, showSleepTimer: true);
            }
          },
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.more_horiz_rounded,
                size: 22, color: AppColors.textPrimary),
          ),
        ),
      ],
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
          color: liked ? track.accent : AppColors.textSecondary,
          size: size,
          shadows: liked
              ? [Shadow(color: track.accent, blurRadius: 16)]
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
            gradient: AppColors.accentSweepOf(widget.accent),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.55),
                blurRadius: 28,
                spreadRadius: -2,
              ),
            ],
          ),
          child: widget.loading
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                      strokeWidth: 2.6, color: Tone.onColor(widget.accent)),
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
                    color: Tone.onColor(widget.accent),
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
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
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
