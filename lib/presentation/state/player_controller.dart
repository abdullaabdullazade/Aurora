import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../core/notifications/notification_service.dart';
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

  void _wireStreams() {
    _player.positionStream.listen((p) {
      if (!state.isLoading) state = state.copyWith(position: p);
    });
    _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _player.playerStateStream.listen((ps) {
      state = state.copyWith(isPlaying: ps.playing);
      if (ps.processingState == ja.ProcessingState.completed) _onComplete();
    });
  }

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
    if (state.repeat == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      next();
    }
  }

  // Resolves the current track on-device (residential IP) and plays it.
  Future<void> _loadCurrent({bool autoplay = false}) async {
    final track = state.current;
    if (track == null) return;
    final token = ++_loadToken;
    state = state.copyWith(isLoading: true, position: Duration.zero);
    _recordRecent(track);
    try {
      final uri = track.localPath != null
          ? Uri.file(track.localPath!)
          : await ref.read(musicRepositoryProvider).resolveStream(track);
      if (token != _loadToken) return;
      // Proxy/local serve clean audio — no special CDN headers needed.
      await _player.setAudioSource(
          ja.AudioSource.uri(uri, tag: _media(track)));
      if (token != _loadToken) return;
      state = state.copyWith(isLoading: false);
      if (autoplay) await _player.play();
      _applyPalette(track);
    } catch (e, st) {
      debugPrint('[player] load failed: $e\n$st');
      if (token == _loadToken) {
        state = state.copyWith(isLoading: false, error: 'Playback failed');
      }
    }
  }

  // --- Volume ------------------------------------------------------------
  Future<void> setVolume(double v) async {
    final vol = v.clamp(0.0, 1.0);
    _baseVolume = vol;
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

  void setSleep(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration == null) {
      _sleepEnd = null;
      _player.setVolume(_baseVolume);
      state = state.copyWith(clearSleep: true);
      return;
    }
    _sleepEnd = DateTime.now().add(duration);
    state = state.copyWith(sleepRemaining: duration);
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
    await ref.read(localStoreProvider).pushRecent(t);
    ref.invalidate(recentlyPlayedProvider);
  }

  Future<void> _applyPalette(Track track) async {
    if (track.artworkUrl.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(track.artworkUrl),
        size: const Size(120, 120),
        maximumColorCount: 8,
      );
      final Color? raw =
          palette.vibrantColor?.color ?? palette.dominantColor?.color;
      if (raw == null) return;
      // Normalize so the accent is always vivid + readable on the dark veil
      // (raw pale-yellow palettes clashed with UI elements).
      final hsl = HSLColor.fromColor(raw);
      final c = hsl
          .withSaturation(hsl.saturation.clamp(0.55, 1.0))
          .withLightness(hsl.lightness.clamp(0.45, 0.62))
          .toColor();
      final list = [...state.queue];
      final i = list.indexWhere((e) => e.id == track.id);
      if (i >= 0) {
        list[i] = list[i].copyWith(accent: c);
        state = state.copyWith(queue: list);
      }
    } catch (_) {/* keep deterministic accent */}
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
