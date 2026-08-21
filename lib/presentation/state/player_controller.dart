import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../core/config/app_config.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/dynamic_palette.dart';
import '../../domain/entities/track.dart';
import 'providers.dart';

enum LoopMode { off, one, all }

@immutable
class PlayerState {
  final List<Track> queue;
  final int index;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final LoopMode repeat;
  final String? error;
  final double volume;
  final Duration? sleepRemaining;
  final double speed;

  /// Stop playback when the current track ends, instead of at a wall clock.
  final bool sleepAtTrackEnd;

  const PlayerState({
    this.queue = const [],
    this.index = 0,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = LoopMode.off,
    this.error,
    this.volume = 1.0,
    this.sleepRemaining,
    this.speed = 1.0,
    this.sleepAtTrackEnd = false,
  });

  Track? get current =>
      (queue.isNotEmpty && index >= 0 && index < queue.length)
          ? queue[index]
          : null;

  bool get hasTrack => current != null;

  Duration get total => duration > Duration.zero
      ? duration
      : (current?.duration ?? Duration.zero);

  double get progress => total.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

  PlayerState copyWith({
    List<Track>? queue,
    int? index,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    bool? shuffle,
    LoopMode? repeat,
    String? error,
    double? volume,
    Duration? sleepRemaining,
    bool clearSleep = false,
    double? speed,
    bool? sleepAtTrackEnd,
  }) =>
      PlayerState(
        queue: queue ?? this.queue,
        index: index ?? this.index,
        isPlaying: isPlaying ?? this.isPlaying,
        isLoading: isLoading ?? this.isLoading,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        error: error,
        volume: volume ?? this.volume,
        sleepRemaining:
            clearSleep ? null : (sleepRemaining ?? this.sleepRemaining),
        speed: speed ?? this.speed,
        // Independent of clearSleep: "stop after this track" is set *while*
        // the countdown is being cleared, so folding them together would
        // switch the flag off the moment it is switched on.
        sleepAtTrackEnd: sleepAtTrackEnd ?? this.sleepAtTrackEnd,
      );
}

/// Playback engine on just_audio. The whole queue is loaded as a
/// ConcatenatingAudioSource so the OS lock-screen / notification gets real
/// next / previous / seek controls and playback is gapless.
class PlayerController extends Notifier<PlayerState> {
  late final ja.AudioPlayer _player;
  late final ja.AndroidEqualizer equalizer; // exposed to the EQ screen
  Timer? _sleepTimer;
  DateTime? _sleepEnd;
  double _baseVolume = 1.0;

  @override
  PlayerState build() {
    equalizer = ja.AndroidEqualizer();
    _player = ja.AudioPlayer(
      audioPipeline: ja.AudioPipeline(androidAudioEffects: [equalizer]),
    );
    _wireStreams();
    _wireAudioSession();
    ref.onDispose(() {
      _sleepTimer?.cancel();
      _fadeTimer?.cancel();
      _player.dispose();
    });
    return const PlayerState();
  }

  Future<void> _wireAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) _player.pause();
    });
  }

  int _loadToken = 0;

  /// Position of the last tick, used to accumulate real listening time.
  /// Seeks and track switches produce jumps, so only small forward deltas
  /// count — otherwise scrubbing would inflate the stats.
  Duration _lastTick = Duration.zero;
  String? _lastTickId;
  int _pendingSeconds = 0;

  void _wireStreams() {
    _player.positionStream.listen((p) {
      if (!state.isLoading) state = state.copyWith(position: p);
      _maybeFadeOut();
      final id = state.current?.id;
      if (id != null && id == _lastTickId) {
        final delta = p - _lastTick;
        if (delta > Duration.zero && delta < const Duration(seconds: 2)) {
          _pendingSeconds += delta.inMilliseconds;
          if (_pendingSeconds >= 15000) {
            ref
                .read(localStoreProvider)
                .addListenTime(id, _pendingSeconds ~/ 1000);
            _pendingSeconds = 0;
          }
        }
      }
      _lastTickId = id;
      _lastTick = p;
    });
    _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _player.playerStateStream.listen((ps) {
      state = state.copyWith(isPlaying: ps.playing);
      if (ps.processingState == ja.ProcessingState.completed) _onComplete();
    });
    // Handle skip buttons from the lock-screen / notification. When the user
    // taps next/prev there, just_audio changes the index inside the
    // ConcatenatingAudioSource. We translate that into our queue navigation.
    _player.currentIndexStream.listen((newIdx) {
      if (newIdx == null || _isHandlingNotifSkip) return;
      // _concatBaseIndex is the position of the "current" track within the
      // ConcatenatingAudioSource window (0 if first in queue, else 1).
      if (newIdx > _concatBaseIndex) {
        _isHandlingNotifSkip = true;
        next().whenComplete(() => _isHandlingNotifSkip = false);
      } else if (newIdx < _concatBaseIndex) {
        _isHandlingNotifSkip = true;
        previous().whenComplete(() => _isHandlingNotifSkip = false);
      }
    });
  }

  /// Index of the "current" track within the ConcatenatingAudioSource window.
  int _concatBaseIndex = 0;
  bool _isHandlingNotifSkip = false;

  MediaItem _media(Track t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        duration: t.duration > Duration.zero ? t.duration : null,
        artUri: t.artworkUrl.isNotEmpty ? Uri.parse(t.artworkUrl) : null,
      );

  Future<void> playQueue(List<Track> tracks, {int startAt = 0}) async {
    if (tracks.isEmpty) return;
    state = state.copyWith(
      queue: tracks,
      index: startAt.clamp(0, tracks.length - 1),
      position: Duration.zero,
      duration: Duration.zero,
    );
    await _loadCurrent(autoplay: true);
  }

  void playSingle(Track track) => playQueue([track]);

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> pause() async {
    if (_player.playing) {
      await _player.pause();
    }
  }

  Future<void> next() async {
    if (state.queue.isEmpty) return;
    final last = state.index >= state.queue.length - 1;
    if (last && state.repeat == LoopMode.off && state.queue.length > 1) {
      // wrap so "next" always does something
    } else if (last && state.queue.length == 1) {
      return;
    }
    state = state.copyWith(
        index: last ? 0 : state.index + 1,
        position: Duration.zero,
        duration: Duration.zero);
    await _loadCurrent(autoplay: true);
  }

  Future<void> previous() async {
    if (state.position.inSeconds > 3 || state.index == 0) {
      await _player.seek(Duration.zero);
      return;
    }
    state = state.copyWith(
        index: state.index - 1,
        position: Duration.zero,
        duration: Duration.zero);
    await _loadCurrent(autoplay: true);
  }

  Future<void> seek(double fraction) =>
      _player.seek(state.total * fraction.clamp(0.0, 1.0));

  void _onComplete() {
    // "Stop after this track" wins over every continuation rule.
    if (state.sleepAtTrackEnd) {
      _sleepTimer?.cancel();
      _player.pause();
      _player.setVolume(_baseVolume);
      state = state.copyWith(clearSleep: true, sleepAtTrackEnd: false);
      NotificationService.instance.showNow(
          2001, '😴 Sleep timer ended', 'Playback paused. Sweet dreams.');
      return;
    }
    if (state.repeat == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    next();
  }

  // Resolves the current track on-device (residential IP) and plays it.
  Future<void> _loadCurrent({bool autoplay = false}) async {
    final track = state.current;
    if (track == null) return;
    final token = ++_loadToken;
    _cancelFade();
    state = state.copyWith(isLoading: true, position: Duration.zero);
    _recordRecent(track);
    try {
      final uri = track.localPath != null
          ? Uri.file(track.localPath!)
          : await ref.read(musicRepositoryProvider).resolveStream(track);
      if (token != _loadToken) return;

      // Build a 3-item ConcatenatingAudioSource (prev / current / next) so
      // just_audio_background shows skip-prev and skip-next on the lock-screen
      // and notification. The window is rebuilt on every track change.
      final q = state.queue;
      final idx = state.index;
      final sources = <ja.AudioSource>[];
      int initialIndex = 0;

      if (q.length == 1) {
        // Single track — no neighbours
        sources.add(ja.AudioSource.uri(uri, tag: _media(track)));
      } else {
        // Previous track (placeholder — will be replaced when actually played)
        if (idx > 0) {
          final prev = q[idx - 1];
          final prevUri = prev.localPath != null
              ? Uri.file(prev.localPath!)
              : Uri.parse('${AppConfig.apiBase}/stream?v=${prev.id}');
          sources.add(ja.AudioSource.uri(prevUri, tag: _media(prev)));
          initialIndex = 1;
        }
        // Current track
        sources.add(ja.AudioSource.uri(uri, tag: _media(track)));
        // Next track (placeholder)
        if (idx < q.length - 1) {
          final nxt = q[idx + 1];
          final nxtUri = nxt.localPath != null
              ? Uri.file(nxt.localPath!)
              : Uri.parse('${AppConfig.apiBase}/stream?v=${nxt.id}');
          sources.add(ja.AudioSource.uri(nxtUri, tag: _media(nxt)));
        }
      }

      _concatBaseIndex = initialIndex;
      _isHandlingNotifSkip = true;
      await _player.setAudioSource(
        ja.ConcatenatingAudioSource(children: sources),
        initialIndex: initialIndex,
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        _isHandlingNotifSkip = false;
      });
      if (token != _loadToken) return;
      state = state.copyWith(isLoading: false);
      if (autoplay) {
        _fadeIn();
        await _player.play();
      } else {
        await _player.setVolume(_baseVolume);
      }
      _applyPalette(track);
    } catch (e, st) {
      debugPrint('[player] load failed: $e\n$st');
      if (token == _loadToken) {
        state = state.copyWith(isLoading: false, error: 'Playback failed');
      }
    }
  }

  // --- Crossfade ----------------------------------------------------------
  // One player can only render one stream, so this is a fade-out into a
  // fade-in rather than two tracks overlapping. It removes the hard cut
  // between songs, which is what the setting is for; a true overlap would
  // need a second AudioPlayer, and just_audio_background only accepts one.
  Timer? _fadeTimer;
  bool _fadingOut = false;

  void _maybeFadeOut() {
    if (_fadingOut || !state.isPlaying || state.isLoading) return;
    if (!ref.read(crossfadeProvider)) return;
    // The sleep timer owns the volume during its own fade — don't fight it.
    if (state.sleepRemaining != null) return;
    final total = state.total;
    if (total <= Duration.zero) return;
    final window = Duration(seconds: ref.read(crossfadeSecondsProvider));
    final left = total - state.position;
    if (left <= Duration.zero || left > window) return;
    _fadingOut = true;
    _ramp(from: _baseVolume, to: 0, over: left);
  }

  void _fadeIn() {
    if (!ref.read(crossfadeProvider)) return;
    _ramp(
      from: 0,
      to: _baseVolume,
      over: Duration(seconds: ref.read(crossfadeSecondsProvider)),
    );
  }

  void _ramp({
    required double from,
    required double to,
    required Duration over,
  }) {
    _fadeTimer?.cancel();
    const step = Duration(milliseconds: 60);
    final steps = (over.inMilliseconds / step.inMilliseconds).ceil();
    if (steps <= 1) {
      _player.setVolume(to);
      return;
    }
    var i = 0;
    _player.setVolume(from);
    _fadeTimer = Timer.periodic(step, (t) {
      i++;
      final v = from + (to - from) * (i / steps);
      _player.setVolume(v.clamp(0.0, 1.0));
      if (i >= steps) t.cancel();
    });
  }

  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadingOut = false;
  }

  // --- Volume ------------------------------------------------------------
  Future<void> setVolume(double v) async {
    final vol = v.clamp(0.0, 1.0);
    _baseVolume = vol;
    // A deliberate volume change outranks any fade in flight.
    _cancelFade();
    await _player.setVolume(vol);
    state = state.copyWith(volume: vol);
  }

  Future<void> adjustVolume(double delta) => setVolume(_baseVolume + delta);

  // --- Speed -------------------------------------------------------------
  static const speeds = [0.5, 1.0, 1.25, 1.5, 2.0];

  Future<void> cycleSpeed() async {
    final i = speeds.indexWhere((s) => (s - state.speed).abs() < 0.01);
    final nextSpeed = speeds[(i + 1) % speeds.length];
    await _player.setSpeed(nextSpeed);
    state = state.copyWith(speed: nextSpeed);
  }

  // --- Shuffle / repeat (handled in _onComplete / next) -----------------
  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);

  void cycleRepeat() {
    const order = LoopMode.values;
    state =
        state.copyWith(repeat: order[(state.repeat.index + 1) % order.length]);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final list = [...state.queue];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    var idx = state.index;
    if (oldIndex == state.index) {
      idx = newIndex;
    } else if (oldIndex < state.index && newIndex >= state.index) {
      idx -= 1;
    } else if (oldIndex > state.index && newIndex <= state.index) {
      idx += 1;
    }
    state = state.copyWith(queue: list, index: idx);
  }

  // --- Sleep timer (with 10s fade-out) ----------------------------------
  static const _fadeWindow = Duration(seconds: 10);

  /// Stop once the current track finishes. No countdown and no fade — the
  /// track's own ending is the fade.
  void sleepAfterTrack() {
    _sleepTimer?.cancel();
    _sleepEnd = null;
    _player.setVolume(_baseVolume);
    state = state.copyWith(clearSleep: true, sleepAtTrackEnd: true);
  }

  void setSleep(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration == null) {
      _sleepEnd = null;
      _player.setVolume(_baseVolume);
      state = state.copyWith(clearSleep: true, sleepAtTrackEnd: false);
      return;
    }
    _sleepEnd = DateTime.now().add(duration);
    state =
        state.copyWith(sleepRemaining: duration, sleepAtTrackEnd: false);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _sleepEnd!.difference(DateTime.now());
      if (left <= Duration.zero) {
        _sleepTimer?.cancel();
        _player.pause();
        _player.setVolume(_baseVolume);
        state = state.copyWith(clearSleep: true);
        NotificationService.instance.showNow(
            2001, '😴 Sleep timer ended', 'Playback paused. Sweet dreams.');
        return;
      }
      if (left <= _fadeWindow) {
        final f = left.inMilliseconds / _fadeWindow.inMilliseconds;
        _player.setVolume(_baseVolume * f.clamp(0.0, 1.0));
      }
      state = state.copyWith(sleepRemaining: left);
    });
  }

  // --- internal ----------------------------------------------------------
  Future<void> _recordRecent(Track t) async {
    final store = ref.read(localStoreProvider);
    await store.pushRecent(t);
    await store.bumpPlay(t);
    ref.invalidate(recentlyPlayedProvider);
    ref.invalidate(listeningStatsProvider);
  }

  Future<void> _applyPalette(Track track) async {
    if (track.artworkUrl.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(track.artworkUrl),
        size: const Size(120, 120),
        maximumColorCount: 8,
      );
      final Color? raw = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color;
      if (raw == null) return;
      // Store the *mark* color only. The screen wash is derived from it at
      // paint time (Tone.backdrop) — painting this vivid color full-screen is
      // what used to bury every secondary label.
      final c = Tone.accent(raw);
      final list = [...state.queue];
      final i = list.indexWhere((e) => e.id == track.id);
      if (i >= 0) {
        list[i] = list[i].copyWith(accent: c, paletteReady: true);
        state = state.copyWith(queue: list);
      }
    } catch (_) {/* keep deterministic accent */}
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
