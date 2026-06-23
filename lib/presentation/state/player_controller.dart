import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/track.dart';

enum LoopMode { off, one, all }

@immutable
class PlayerState {
  final List<Track> queue;
  final int index;
  final bool isPlaying;
  final Duration position;
  final bool shuffle;
  final LoopMode repeat;

  const PlayerState({
    this.queue = const [],
    this.index = 0,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.shuffle = false,
    this.repeat = LoopMode.off,
  });

  Track? get current =>
      (queue.isNotEmpty && index >= 0 && index < queue.length)
          ? queue[index]
          : null;

  bool get hasTrack => current != null;
  Duration get total => current?.duration ?? Duration.zero;
  double get progress => total.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

  PlayerState copyWith({
    List<Track>? queue,
    int? index,
    bool? isPlaying,
    Duration? position,
    bool? shuffle,
    LoopMode? repeat,
  }) =>
      PlayerState(
        queue: queue ?? this.queue,
        index: index ?? this.index,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
      );
}

/// Drives playback state. Here it simulates a ticking position so the UI is
/// fully alive in preview. In production, replace [_tick] wiring with
/// just_audio's positionStream and forward transport calls to AudioHandler.
class PlayerController extends Notifier<PlayerState> {
  Timer? _ticker;

  @override
  PlayerState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const PlayerState();
  }

  void playQueue(List<Track> tracks, {int startAt = 0}) {
    state = state.copyWith(
      queue: tracks,
      index: startAt,
      position: Duration.zero,
      isPlaying: true,
    );
    _restartTicker();
  }

  void playSingle(Track track) => playQueue([track]);

  void toggle() {
    state = state.copyWith(isPlaying: !state.isPlaying);
    state.isPlaying ? _restartTicker() : _ticker?.cancel();
  }

  void next() {
    if (state.queue.isEmpty) return;
    final last = state.index >= state.queue.length - 1;
    if (last && state.repeat == LoopMode.off) {
      _seekTo(state.total);
      return;
    }
    final nextIndex = last ? 0 : state.index + 1;
    state = state.copyWith(
        index: nextIndex, position: Duration.zero, isPlaying: true);
    _restartTicker();
  }

  void previous() {
    if (state.position.inSeconds > 3 || state.index == 0) {
      _seekTo(Duration.zero);
      return;
    }
    state = state.copyWith(
        index: state.index - 1, position: Duration.zero, isPlaying: true);
    _restartTicker();
  }

  void seek(double fraction) =>
      _seekTo(state.total * fraction.clamp(0.0, 1.0));

  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);

  void cycleRepeat() {
    const order = LoopMode.values;
    state = state.copyWith(
        repeat: order[(state.repeat.index + 1) % order.length]);
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
  void _seekTo(Duration p) =>
      state = state.copyWith(position: p > state.total ? state.total : p);

  void _restartTicker() {
    _ticker?.cancel();
    if (!state.isPlaying) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final next = state.position + const Duration(milliseconds: 250);
      if (next >= state.total) {
        if (state.repeat == LoopMode.one) {
          _seekTo(Duration.zero);
        } else {
          this.next();
        }
        return;
      }
      _seekTo(next);
    });
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
