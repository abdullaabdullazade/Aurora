import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:palette_generator/palette_generator.dart';
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
  final Duration duration; // real stream duration once known
  final bool shuffle;
  final LoopMode repeat;
  final String? error;

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
  });

  Track? get current =>
      (queue.isNotEmpty && index >= 0 && index < queue.length)
          ? queue[index]
          : null;

  bool get hasTrack => current != null;

  Duration get total =>
      duration > Duration.zero ? duration : (current?.duration ?? Duration.zero);

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
      );
}

/// Real playback engine on top of just_audio. Resolves a YouTube audio stream
/// per track on demand, extracts a palette color for the ambient UI, and
/// records recents to the local store.
class PlayerController extends Notifier<PlayerState> {
  late final AudioPlayer _player;
  int _loadToken = 0; // guards against out-of-order async loads

  @override
  PlayerState build() {
    _player = AudioPlayer();
    _wireStreams();
    ref.onDispose(_player.dispose);
    return const PlayerState();
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
      if (ps.processingState == ProcessingState.completed) _onComplete();
    });
  }

  Future<void> playQueue(List<Track> tracks, {int startAt = 0}) async {
    state = state.copyWith(
      queue: tracks,
      index: startAt,
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
    if (last && state.repeat == LoopMode.off) return;
    final nextIndex = last ? 0 : state.index + 1;
    state = state.copyWith(
        index: nextIndex, position: Duration.zero, duration: Duration.zero);
    await _loadCurrent(autoplay: true);
  }

  Future<void> previous() async {
    if (state.position.inSeconds > 3 || state.index == 0) {
      await _player.seek(Duration.zero);
      return;
    }
    state = state.copyWith(
        index: state.index - 1, position: Duration.zero, duration: Duration.zero);
    await _loadCurrent(autoplay: true);
  }

  Future<void> seek(double fraction) =>
      _player.seek(state.total * fraction.clamp(0.0, 1.0));

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

  // --- internal ----------------------------------------------------------
  void _onComplete() {
    if (state.repeat == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      next();
    }
  }

  Future<void> _loadCurrent({bool autoplay = false}) async {
    final track = state.current;
    if (track == null) return;
    final token = ++_loadToken;
    state = state.copyWith(isLoading: true, position: Duration.zero);

    // Record recent + refresh the Home carousel.
    await ref.read(localStoreProvider).pushRecent(track);
    ref.invalidate(recentlyPlayedProvider);

    try {
      final uri = await ref.read(musicRepositoryProvider).resolveStream(track);
      if (token != _loadToken) return; // superseded by a newer load
      debugPrint('[player] resolved stream for "${track.title}"');
      // ExoPlayer's default `Accept-Encoding: gzip` makes the YouTube CDN
      // return 403 on these (already-compressed) range requests; force
      // `identity` and use the matching ANDROID-client User-Agent.
      await _player.setAudioSource(
        AudioSource.uri(uri, headers: const {
          'Accept-Encoding': 'identity',
          'User-Agent':
              'com.google.android.youtube/19.09.37 (Linux; U; Android 14) gzip',
        }),
      );
      if (token != _loadToken) return;
      state = state.copyWith(isLoading: false);
      if (autoplay) await _player.play();
      _applyPalette(track, token); // fire-and-forget
    } catch (e, st) {
      debugPrint('[player] load failed for "${track.title}": $e\n$st');
      if (token == _loadToken) {
        state = state.copyWith(isLoading: false, error: 'Playback failed');
      }
    }
  }

  /// Extracts a dominant color from the artwork and recolors the active track
  /// so the ambient background matches it.
  Future<void> _applyPalette(Track track, int token) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(track.artworkUrl),
        size: const Size(120, 120),
        maximumColorCount: 8,
      );
      final Color? c = palette.vibrantColor?.color ??
          palette.dominantColor?.color;
      if (c == null || token != _loadToken) return;
      final list = [...state.queue];
      if (state.index < list.length) {
        list[state.index] = list[state.index].copyWith(accent: c);
        state = state.copyWith(queue: list);
      }
    } catch (_) {/* keep deterministic accent */}
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
