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
  ja.ConcatenatingAudioSource? _playlist;
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

  void _wireStreams() {
    _player.positionStream.listen((p) {
      if (!state.isLoading) state = state.copyWith(position: p);
    });
    _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _player.playerStateStream.listen((ps) {
      state = state.copyWith(isPlaying: ps.playing);
    });
    // The OS controls (and gapless advance) drive the index — mirror it.
    _player.currentIndexStream.listen((i) {
      if (i == null || i < 0 || i >= state.queue.length) return;
      if (i == state.index) return;
      state = state.copyWith(index: i, position: Duration.zero);
      final t = state.queue[i];
      _recordRecent(t);
      _applyPalette(t);
    });
  }

  Uri _uriFor(Track t) => t.localPath != null
      ? Uri.file(t.localPath!)
      : Uri.parse('${AppConfig.apiBase}/stream?v=${t.id}');

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
      index: startAt,
      position: Duration.zero,
      duration: Duration.zero,
      isLoading: true,
    );
    try {
      _playlist = ja.ConcatenatingAudioSource(
        children: [for (final t in tracks) ja.AudioSource.uri(_uriFor(t), tag: _media(t))],
      );
      await _player.setAudioSource(_playlist!,
          initialIndex: startAt, initialPosition: Duration.zero);
      state = state.copyWith(isLoading: false);
      _recordRecent(tracks[startAt]);
      _applyPalette(tracks[startAt]);
      await _player.play();
    } catch (e, st) {
      debugPrint('[player] queue load failed: $e\n$st');
      state = state.copyWith(isLoading: false, error: 'Playback failed');
    }
  }

  void playSingle(Track track) => playQueue([track]);

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() => _player.seekToNext();

  Future<void> previous() async {
    if (state.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  Future<void> seek(double fraction) =>
      _player.seek(state.total * fraction.clamp(0.0, 1.0));

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

  // --- Shuffle / repeat (native, so OS controls stay in sync) -----------
  Future<void> toggleShuffle() async {
    final on = !state.shuffle;
    await _player.setShuffleModeEnabled(on);
    state = state.copyWith(shuffle: on);
  }

  Future<void> cycleRepeat() async {
    const order = LoopMode.values;
    final next = order[(state.repeat.index + 1) % order.length];
    await _player.setLoopMode(switch (next) {
      LoopMode.off => ja.LoopMode.off,
      LoopMode.one => ja.LoopMode.one,
      LoopMode.all => ja.LoopMode.all,
    });
    state = state.copyWith(repeat: next);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final list = [...state.queue];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    _playlist?.move(oldIndex, newIndex);
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
      final Color? c =
          palette.vibrantColor?.color ?? palette.dominantColor?.color;
      if (c == null) return;
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
