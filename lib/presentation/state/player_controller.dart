import 'dart:async';
import 'dart:io';
import 'dart:math';
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
import '../../data/datasources/yt_stream_resolver.dart';
import '../../domain/entities/track.dart';
import '../../core/db/sync_service.dart';
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

  Track? get current => (queue.isNotEmpty && index >= 0 && index < queue.length)
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

class _StreamUnavailable extends HttpException {
  _StreamUnavailable(Uri uri) : super('stream unavailable (404)', uri: uri);
}

/// Playback engine on just_audio. Remote tracks are a single AudioSource.uri
/// so end-of-stream is detectable; the Dart queue decides what plays next.
class PlayerController extends Notifier<PlayerState> {
  late ja.AudioPlayer _player;
  late ja.AndroidEqualizer equalizer; // exposed to the EQ screen
  int _playerGeneration = 0;
  Timer? _sleepTimer;
  DateTime? _sleepEnd;
  double _baseVolume = 1.0;
  static const _persistInterval = Duration(seconds: 5);
  DateTime _lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _positionPoll;
  bool _wasPlaying = false;
  bool _advancing = false;
  bool _userPaused = false;
  bool _sessionRestorePending = false;
  Duration _restoredStartAt = Duration.zero;

  /// A source was loaded without autoplay (restored session); stays set until
  /// something actually starts playback, so app resume does not auto-play it.
  bool _loadedPaused = false;

  /// Whether the in-flight load should start playing. Toggle flips it while
  /// loading instead of restarting the load.
  bool _autoplayRequested = false;
  Duration? _seekDuringLoad;
  String? _advanceFromId;
  DateTime? _stuckSince;
  int _midStreamReloadCount = 0;
  bool _handlingStreamError = false;
  String? _warmingId;

  /// Next track whose warm-up got a 404, so its load fails at once.
  String? _unavailableId;
  HttpClient? _warmClient;
  Future<void>? _warmFuture;
  HttpClient? _loadProbeClient;
  Future<void>? _recreating;

  @override
  PlayerState build() {
    _createPlayer();
    _wireAudioSession();
    listenSelf((_, next) => _syncNotificationControls(next));
    ref.onDispose(() {
      JustAudioBackground.clearQueueControls();
      _sleepTimer?.cancel();
      _fadeTimer?.cancel();
      _stopPositionPoll();
      _cancelWarm();
      _closeLoadProbe();
      _player.dispose();
    });
    final initial = _initialStateFromSession() ?? const PlayerState();
    _syncNotificationControls(initial);
    return initial;
  }

  ({bool previous, bool next})? _notificationSkips;

  /// just_audio only ever holds the current remote track, so the
  /// notification / lock screen / headset skip buttons follow this queue.
  /// next() wraps to the start, matching the in-app button.
  void _syncNotificationControls(PlayerState s) {
    final skips = (previous: s.queue.isNotEmpty, next: s.queue.length > 1);
    if (skips == _notificationSkips) return;
    _notificationSkips = skips;
    JustAudioBackground.setQueueControls(
      hasPrevious: skips.previous,
      hasNext: skips.next,
      onNext: next,
      onPrevious: previous,
    );
  }

  /// Restores queue/position for the mini-player without loading audio yet.
  PlayerState? _initialStateFromSession() {
    if (!ref.read(resumePlaybackProvider)) return null;
    final session = ref.read(localStoreProvider).playbackSession();
    if (session == null) return null;

    final queue = _enrichQueue(session.queue);
    final index = session.index.clamp(0, queue.length - 1);
    _sessionRestorePending = true;
    _restoredStartAt = session.position;
    Future.microtask(_preloadRestoredSession);
    return PlayerState(
      queue: queue,
      index: index,
      position: session.position,
      duration: queue[index].duration,
    );
  }

  /// Load the restored track paused, so play on the notification, lock screen
  /// or a headset works right after a cold start, not only the in-app button.
  void _preloadRestoredSession() {
    if (!_sessionRestorePending || !state.hasTrack) return;
    unawaited(_loadCurrent(
      autoplay: false,
      startAt: _restoredStartAt,
      recordRecent: false,
    ));
  }

  void _createPlayer() {
    equalizer = ja.AndroidEqualizer();
    _player = ja.AudioPlayer(
      audioPipeline: ja.AudioPipeline(androidAudioEffects: [equalizer]),
      audioLoadConfiguration: const ja.AudioLoadConfiguration(
        androidLoadControl: ja.AndroidLoadControl(
          minBufferDuration: Duration(seconds: 15),
          maxBufferDuration: Duration(seconds: 50),
          bufferForPlaybackDuration: Duration(seconds: 2),
          bufferForPlaybackAfterRebufferDuration: Duration(seconds: 5),
        ),
      ),
    );
    _wireStreams(_player, ++_playerGeneration);
  }

  /// Replace a native player that stopped accepting sources.
  /// Must dispose the old instance first — just_audio_background allows only
  /// one player id at a time.
  /// Concurrent callers share one recreate, and loads wait for it via
  /// [_awaitPlayerRecreate] so no source is set on a player being disposed.
  Future<void> _recreatePlayer() {
    return _recreating ??= () async {
      try {
        _stopPositionPoll();
        _concat = null;
        _windowQueueIndices = [];
        final broken = _player;
        try {
          await broken.dispose();
        } catch (e) {
          debugPrint('[player] dispose before recreate failed: $e');
        }
        _createPlayer();
        await _player.setVolume(_baseVolume);
        await _player.setSpeed(state.speed);
      } finally {
        _recreating = null;
      }
    }();
  }

  Future<void> _awaitPlayerRecreate() async {
    final pending = _recreating;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
  }

  Future<void> _wireAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) unawaited(_pauseInternal());
    });
  }

  int _loadToken = 0;

  /// just_audio can leave setAudioSource pending forever when platform
  /// activation fails; treat that as a broken native player and recreate it.
  static const _setSourceTimeout = Duration(seconds: 30);

  /// Position of the last tick, used to accumulate real listening time.
  /// Seeks and track switches produce jumps, so only small forward deltas
  /// count — otherwise scrubbing would inflate the stats.
  Duration _lastTick = Duration.zero;
  String? _lastTickId;
  int _pendingSeconds = 0;

  void _stopPositionPoll() {
    _positionPoll?.cancel();
    _positionPoll = null;
  }

  void _syncPositionPoll(bool playing) {
    if (!playing || _sessionRestorePending) {
      _stopPositionPoll();
      return;
    }
    if (_positionPoll != null) return;
    // Poll like Android media notification interpolation — just_audio's
    // positionStream often stalls after setAudioSource / missing duration.
    _positionPoll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_player.playing || _sessionRestorePending) {
        _stopPositionPoll();
        return;
      }
      _onPositionTick(_player.position, fromPoll: true);
    });
  }

  void _onPositionTick(Duration p, {required bool fromPoll}) {
    final grew = p > _lastTick + const Duration(milliseconds: 80);
    if (fromPoll && !_sessionRestorePending) {
      final d = _player.duration;
      state = state.copyWith(
        position: p,
        duration: d ?? state.duration,
      );
    }
    if (!_sessionRestorePending && !state.isLoading) {
      if (_fadingOut) {
        _stuckSince = null;
      } else if (state.isPlaying && state.total > Duration.zero) {
        final progress = state.total.inMilliseconds == 0
            ? 0.0
            : (p.inMilliseconds / state.total.inMilliseconds).clamp(0.0, 1.0);
        final left = state.total - p;
        if (progress >= 0.995 && !grew && left <= const Duration(seconds: 1)) {
          _stuckSince ??= DateTime.now();
          if (DateTime.now().difference(_stuckSince!) >=
              const Duration(seconds: 3)) {
            final id = state.current?.id;
            if (id != null) {
              _advanceToNext(fromTrackId: id, reason: 'stuck');
            }
          }
        } else {
          _stuckSince = null;
        }
      } else {
        _stuckSince = null;
      }
    }
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
    if (!_sessionRestorePending) _schedulePersistSession();
  }

  void _wireStreams(ja.AudioPlayer player, int generation) {
    bool isCurrentPlayer() => generation == _playerGeneration;

    // Side-effects only — UI position comes from _positionPoll.
    player.positionStream.listen((p) {
      if (!isCurrentPlayer()) return;
      _onPositionTick(p, fromPoll: false);
    });
    player.durationStream.listen((d) {
      if (!isCurrentPlayer()) return;
      if (d != null) state = state.copyWith(duration: d);
    });
    player.playerStateStream.listen((ps) {
      if (!isCurrentPlayer()) return;
      final wasPlaying = _wasPlaying;
      state = state.copyWith(isPlaying: ps.playing);
      if (ps.playing) _loadedPaused = false;
      _syncPositionPoll(ps.playing);
      if (wasPlaying && !ps.playing) {
        unawaited(persistSessionNow());
      }
      _wasPlaying = ps.playing;
      final id = state.current?.id;
      if (id == null) return;
      if (ps.processingState == ja.ProcessingState.completed) {
        _advanceToNext(fromTrackId: id, reason: 'completed');
        return;
      }
      if (wasPlaying &&
          !ps.playing &&
          !_userPaused &&
          ps.processingState == ja.ProcessingState.idle &&
          _isNearEnd()) {
        _advanceToNext(fromTrackId: id, reason: 'idle-end');
      }
    });
    player.currentIndexStream.listen((newIdx) {
      if (!isCurrentPlayer()) return;
      if (newIdx == null || state.isLoading || _advancing) return;
      if (DateTime.now().difference(_lastSourceSetTime) <
          const Duration(milliseconds: 800)) {
        return;
      }
      _onNativeIndexChanged(newIdx);
    });
    // Mid-stream HTTP / ExoPlayer failures arrive as stream errors (0.9.x has
    // no errorCode on PlaybackEvent). Reload the same track (never skip).
    player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace st) {
      if (!isCurrentPlayer()) return;
      _onPlaybackStreamError(e, st);
    });
  }

  void _onPlaybackStreamError(Object e, StackTrace st) {
    if (state.isLoading || _advancing || _sessionRestorePending) return;
    if (_handlingStreamError) return;
    _handlingStreamError = true;
    debugPrint('[player] stream error: $e\n$st');
    if (_midStreamReloadCount < 3) {
      _midStreamReloadCount++;
      final startAt = state.position;
      unawaited(_loadCurrent(
        autoplay: !_userPaused,
        startAt: startAt,
        recordRecent: false,
        streamRecovery: true,
      ));
    } else {
      _handlingStreamError = false;
      state = state.copyWith(isLoading: false, error: 'Playback failed');
    }
  }

  /// Wait until the resolver has the file cached. ExoPlayer often times out
  /// during a cold yt-dlp download; probing first makes setAudioSource a
  /// fast Range hit on the same URL.
  Future<void> _ensureStreamReady(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
    String? trackId,
  }) async {
    if (!_uriIsRemote(uri)) return;
    if (trackId != null && trackId == _unavailableId) {
      // Only once: a second tap gets a fresh try in case it was transient.
      _unavailableId = null;
      throw _StreamUnavailable(uri);
    }

    // Reuse an in-flight warm for this same track instead of a second GET.
    if (trackId != null &&
        _warmingId == trackId &&
        _warmFuture != null) {
      try {
        await _warmFuture;
        return;
      } on _StreamUnavailable {
        rethrow;
      } catch (_) {
        // Warm failed — fall through to a fresh probe.
      }
    } else if (_warmingId != null && _warmingId != trackId) {
      _cancelWarm();
    }

    // Owned by the current load so the next load can abort it (no global
    // queue: a stale probe must never delay a newly chosen track).
    _closeLoadProbe();
    final client = HttpClient();
    _loadProbeClient = client;
    try {
      await _httpRangeProbe(uri, timeout: timeout, client: client);
    } finally {
      if (identical(_loadProbeClient, client)) _loadProbeClient = null;
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  void _closeLoadProbe() {
    final client = _loadProbeClient;
    _loadProbeClient = null;
    if (client == null) return;
    try {
      client.close(force: true);
    } catch (_) {}
  }

  Future<void> _httpRangeProbe(
    Uri uri, {
    required Duration timeout,
    HttpClient? client,
  }) async {
    final owned = client == null;
    final http = client ?? HttpClient();
    try {
      http.connectionTimeout = const Duration(seconds: 20);
      final req =
          await http.getUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      if (AppConfig.apiSecretKey.isNotEmpty) {
        req.headers.set('x-api-key', AppConfig.apiSecretKey);
      }
      final res = await req.close().timeout(timeout);
      final code = res.statusCode;
      await res.drain<void>();
      if (code == HttpStatus.notFound) {
        throw _StreamUnavailable(uri);
      }
      if (code >= 400) {
        throw HttpException('stream not ready ($code)', uri: uri);
      }
    } finally {
      if (owned) http.close(force: true);
    }
  }

  void _cancelWarm() {
    try {
      _warmClient?.close(force: true);
    } catch (_) {}
    _warmClient = null;
    if (_warmingId != null) {
      debugPrint('[player] warm cancelled id=$_warmingId');
    }
    _warmingId = null;
    _warmFuture = null;
  }

  /// Best-effort Range GET so the next track is already in the server cache
  /// when we advance (avoids ExoPlayer timing out on a cold yt-dlp download).
  Future<void> _warmNextTrack() async {
    if (state.shuffle) return;
    if (!_player.playing) return;
    final q = state.queue;
    if (q.length <= 1) return;
    var nextIdx = state.index + 1;
    if (nextIdx >= q.length) {
      if (state.repeat != LoopMode.all) return;
      nextIdx = 0;
    }
    if (nextIdx == state.index) return;
    final track = q[nextIdx];
    if (track.localPath != null || _isMediaStoreId(track.id)) return;
    if (_warmingId == track.id) return;
    _cancelWarm();
    _warmingId = track.id;
    final client = HttpClient();
    _warmClient = client;
    final future = () async {
      final uri = await ref.read(musicRepositoryProvider).resolveStream(track);
      if (!_uriIsRemote(uri)) return;
      if (_warmingId != track.id) {
        throw StateError('warm superseded');
      }
      await _httpRangeProbe(
        uri,
        timeout: const Duration(seconds: 90),
        client: client,
      );
    }();
    _warmFuture = future;
    try {
      await future;
    } catch (e) {
      debugPrint('[player] warm next failed: $e');
      if (e is _StreamUnavailable) _unavailableId = track.id;
    } finally {
      if (identical(_warmClient, client)) _warmClient = null;
      try {
        client.close(force: true);
      } catch (_) {}
      if (_warmingId == track.id) {
        _warmingId = null;
        _warmFuture = null;
      }
    }
  }

  /// Index of the playing child inside [_concat].
  int _concatBaseIndex = 0;
  DateTime _lastSourceSetTime = DateTime.now();
  ja.ConcatenatingAudioSource? _concat;
  List<int> _windowQueueIndices = [];

  MediaItem _media(Track t) {
    final title = t.title.trim().isEmpty ? 'Unknown' : t.title.trim();
    final artist = t.artist.trim().isEmpty ? 'Unknown artist' : t.artist.trim();
    // Non-zero duration helps older AVRCP displays (e.g. Onkyo) accept TITLE.
    final duration = t.duration > Duration.zero
        ? t.duration
        : const Duration(milliseconds: 1);
    return MediaItem(
      id: t.id,
      title: title,
      artist: artist,
      album: artist,
      displayTitle: title,
      displaySubtitle: artist,
      duration: duration,
      artUri: t.artworkUrl.isNotEmpty ? Uri.parse(t.artworkUrl) : null,
    );
  }

  /// Nudge MediaSession so AVRCP receivers re-read TITLE after a route change.
  Future<void> republishNowPlayingMetadata() async {
    final track = state.current;
    if (track == null) return;
    try {
      final playing = _player.playing;
      if (playing) {
        await _player.pause();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await _player.play();
      }
    } catch (_) {}
  }

  Future<void> playQueue(List<Track> tracks, {int startAt = 0}) async {
    if (tracks.isEmpty) return;
    _sessionRestorePending = false;
    _restoredStartAt = Duration.zero;
    _userPaused = false;
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
    if (state.isLoading) {
      if (_autoplayRequested && !_userPaused) {
        _userPaused = true;
      } else {
        _userPaused = false;
        _autoplayRequested = true;
      }
      return;
    }
    if (_player.playing) {
      await _pauseInternal();
    } else if (_player.processingState == ja.ProcessingState.idle &&
        state.hasTrack) {
      // Cold start, stream failure, or lazy session restore — load (or reload)
      // the source and resume from the saved scrub position.
      final recordRecent = !_sessionRestorePending;
      final startAt =
          _sessionRestorePending ? _restoredStartAt : state.position;
      _sessionRestorePending = false;
      _restoredStartAt = Duration.zero;
      _userPaused = false;
      await _loadCurrent(
        autoplay: true,
        startAt: startAt,
        recordRecent: recordRecent,
      );
    } else {
      _userPaused = false;
      _cancelFade();
      await _player.setVolume(_baseVolume);
      await _player.play();
    }
  }

  Future<void> pause() async {
    if (state.isLoading) {
      _userPaused = true;
      return;
    }
    if (_player.playing) {
      await _pauseInternal();
      await persistSessionNow();
    }
  }

  /// Ends the session: no mini-player, no notification, and nothing to
  /// restore on the next launch. Shuffle/repeat are preferences and stay.
  Future<void> close() async {
    _loadToken++;
    _cancelWarm();
    _closeLoadProbe();
    _cancelFade();
    _sleepTimer?.cancel();
    _sleepEnd = null;
    _stopPositionPoll();
    _sessionRestorePending = false;
    _seekDuringLoad = null;
    _autoplayRequested = false;
    _loadedPaused = false;
    _userPaused = true;
    state = PlayerState(
      shuffle: state.shuffle,
      repeat: state.repeat,
      volume: state.volume,
      speed: state.speed,
    );
    try {
      await _player.stop();
      await _player.setVolume(_baseVolume);
    } catch (e) {
      debugPrint('[player] stop on close failed: $e');
    }
    await ref.read(localStoreProvider).clearPlaybackSession();
  }

  Future<void> _pauseInternal() async {
    _userPaused = true;
    _cancelFade();
    await _player.setVolume(_baseVolume);
    await _player.pause();
  }

  Future<void> next() async {
    if (state.queue.isEmpty) return;
    if (state.queue.length == 1) return;
    final from = state.current?.id;
    if (from != null) _advanceFromId = from;
    int nextIndex;
    if (state.shuffle) {
      final rng = Random();
      do {
        nextIndex = rng.nextInt(state.queue.length);
      } while (nextIndex == state.index);
    } else {
      final last = state.index >= state.queue.length - 1;
      nextIndex = last ? 0 : state.index + 1;
    }
    _userPaused = false;
    state = state.copyWith(
        index: nextIndex,
        position: Duration.zero,
        duration: Duration.zero);
    await _loadCurrent(autoplay: true);
  }

  Future<void> previous() async {
    if (state.position.inSeconds > 3 || state.index == 0) {
      await _seekTo(Duration.zero);
      return;
    }
    _userPaused = false;
    state = state.copyWith(
        index: state.index - 1,
        position: Duration.zero,
        duration: Duration.zero);
    await _loadCurrent(autoplay: true);
  }

  Future<void> seek(double fraction) =>
      _seekTo(state.total * fraction.clamp(0.0, 1.0));

  /// Seeking an empty or still-loading player is a no-op in just_audio, so
  /// remember the target and apply it once the source is set.
  Future<void> _seekTo(Duration p) async {
    if (_sessionRestorePending) _restoredStartAt = p;
    if (state.isLoading ||
        _player.processingState == ja.ProcessingState.idle) {
      if (state.isLoading) _seekDuringLoad = p;
      state = state.copyWith(position: p);
      return;
    }
    await _player.seek(p);
    // The poll only runs while playing; a paused seek must still be saved.
    state = state.copyWith(position: p);
    if (!_player.playing) unawaited(persistSessionNow());
  }

  void _onNativeIndexChanged(int newIdx) {
    if (newIdx < 0 || newIdx >= _windowQueueIndices.length) return;
    if (newIdx == _concatBaseIndex) return;
    final queueIdx = _windowQueueIndices[newIdx];
    _concatBaseIndex = newIdx;
    if (queueIdx == state.index) return;
    _cancelFade();
    unawaited(_player.setVolume(_baseVolume));
    state = state.copyWith(
      index: queueIdx,
      position: Duration.zero,
      duration: _player.duration ?? Duration.zero,
    );
    final track = state.current;
    if (track != null) {
      _recordRecent(track);
      _applyPalette(track);
    }
    unawaited(_prefetchAfterAdvance());
    unawaited(_persistSession());
  }

  bool _isNearEnd() {
    final total = state.total;
    if (total <= Duration.zero) return false;
    final left = total - state.position;
    return state.progress >= 0.96 || left <= const Duration(seconds: 2);
  }

  void _advanceToNext(
      {required String fromTrackId, required String reason}) {
    if (_advanceFromId == fromTrackId) return;
    if (state.current?.id != fromTrackId) return;
    if (state.sleepAtTrackEnd) {
      _advanceFromId = fromTrackId;
      _sleepTimer?.cancel();
      _player.pause();
      _player.setVolume(_baseVolume);
      state = state.copyWith(clearSleep: true, sleepAtTrackEnd: false);
      NotificationService.instance.showNow(
          2001, '😴 Sleep timer ended', 'Playback paused. Sweet dreams.');
      return;
    }
    if (state.repeat == LoopMode.one) {
      unawaited(_player.seek(Duration.zero));
      unawaited(_player.play());
      return;
    }
    if (state.queue.length <= 1) return;
    _advanceFromId = fromTrackId;
    debugPrint('[player] advance from=$fromTrackId reason=$reason');
    unawaited(next());
  }

  /// After returning from background / lock screen: finish a stuck advance or
  /// resume play when the next source loaded but autoplay did not stick.
  Future<void> onAppResumed() async {
    if (_userPaused || _loadedPaused || !state.hasTrack) return;
    if (_sessionRestorePending || state.isLoading || _advancing) return;
    final ps = _player.processingState;
    if (ps == ja.ProcessingState.completed ||
        (ps == ja.ProcessingState.idle && _isNearEnd())) {
      if (state.queue.length <= 1) return;
      await next();
      return;
    }
    if (!_player.playing &&
        ps != ja.ProcessingState.idle &&
        ps != ja.ProcessingState.loading) {
      _cancelFade();
      await _player.setVolume(_baseVolume);
      await _player.play();
    }
  }

  /// MediaStore rows have short numeric ids; YouTube ids are 11 characters.
  static bool _isMediaStoreId(String id) =>
      id.length < 11 && int.tryParse(id) != null;

  Future<Uri> _getTrackUri(Track track) async {
    // Device tracks: use the content URI to bypass Android's scoped storage
    // native caching on fresh permissions. Checked before localPath because
    // older saved sessions dropped the path, and a numeric id must never be
    // sent to the server.
    if (_isMediaStoreId(track.id)) {
      return Uri.parse('content://media/external/audio/media/${track.id}');
    }
    if (track.localPath != null) {
      final path = track.localPath!;
      if (path.startsWith('content://')) return Uri.parse(path);
      if (await File(path).exists()) return Uri.file(path);

      // A restored download record can outlive its app-private file. YouTube
      // IDs are safe to resolve remotely; device-only numeric IDs were handled
      // above and must never be sent to the server.
      if (RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(track.id)) {
        return ref.read(musicRepositoryProvider).resolveStream(track);
      }
      throw StateError('Local audio file no longer exists: $path');
    }
    return await ref.read(musicRepositoryProvider).resolveStream(track);
  }

  Map<String, String>? _headersFor(Uri value) =>
      value.host.endsWith('.googlevideo.com') ? ytStreamHeaders : null;

  ja.AudioSource _audioItem(Track value, Uri valueUri) => ja.AudioSource.uri(
        valueUri,
        tag: _media(value),
        headers: _headersFor(valueUri),
      );

  bool _uriIsRemote(Uri uri) =>
      uri.scheme == 'http' || uri.scheme == 'https';

  Future<void> _prefetchAfterAdvance() async {
    if (state.shuffle) return;
    final concat = _concat;
    if (concat == null) return;
    final qi = state.index;
    final q = state.queue;
    if (qi + 1 >= q.length) return;
    if (_windowQueueIndices.isNotEmpty &&
        _windowQueueIndices.last == qi + 1) {
      return;
    }
    try {
      final track = q[qi + 1];
      final uri = await _getTrackUri(track);
      if (_uriIsRemote(uri)) return;
      if (!identical(_concat, concat)) return;
      await concat.add(_audioItem(track, uri));
      _windowQueueIndices.add(qi + 1);
    } catch (_) {}
    try {
      while (_windowQueueIndices.length > 3 &&
          (_player.currentIndex ?? 0) > 0) {
        if (!identical(_concat, concat)) return;
        await concat.removeAt(0);
        _windowQueueIndices.removeAt(0);
      }
    } catch (_) {}
    _concatBaseIndex = _player.currentIndex ?? _concatBaseIndex;
  }

  Future<({ja.ConcatenatingAudioSource source, int initialIndex})>
      _sourceWindow(
    Track track,
    Uri uri,
    int token,
  ) async {
    final q = state.queue;
    final idx = state.index;
    final sources = <ja.AudioSource>[];
    final indices = <int>[];
    var initialIndex = 0;

    // HTTP streams share one blocking uvicorn worker. Only one /stream
    // connection at a time — never concat a remote next/prev.
    if (_uriIsRemote(uri) || q.length == 1) {
      sources.add(_audioItem(track, uri));
      indices.add(idx);
    } else {
      if (idx > 0) {
        try {
          final previous = q[idx - 1];
          final previousUri = await _getTrackUri(previous);
          if (token != _loadToken) {
            throw ja.PlayerInterruptedException('superseded load');
          }
          if (!_uriIsRemote(previousUri)) {
            sources.add(_audioItem(previous, previousUri));
            indices.add(idx - 1);
            initialIndex = 1;
          }
        } on ja.PlayerInterruptedException {
          rethrow;
        } catch (_) {}
      }
      sources.add(_audioItem(track, uri));
      indices.add(idx);
      if (!state.shuffle && idx < q.length - 1) {
        try {
          final next = q[idx + 1];
          final nextUri = await _getTrackUri(next);
          if (token != _loadToken) {
            throw ja.PlayerInterruptedException('superseded load');
          }
          if (!_uriIsRemote(nextUri)) {
            sources.add(_audioItem(next, nextUri));
            indices.add(idx + 1);
          }
        } on ja.PlayerInterruptedException {
          rethrow;
        } catch (_) {}
      }
    }

    _windowQueueIndices = indices;
    return (
      source: ja.ConcatenatingAudioSource(
        useLazyPreparation: true,
        children: sources,
      ),
      initialIndex: initialIndex,
    );
  }

  // Resolves the current track on-device (residential IP) and plays it.
  Future<void> _loadCurrent({
    bool autoplay = false,
    Duration startAt = Duration.zero,
    bool recordRecent = true,
    bool streamRecovery = false,
  }) async {
    final track = state.current;
    if (track == null) return;
    final token = ++_loadToken;
    // Any explicit load (next/previous/reload) ends the lazy-restore mode.
    _sessionRestorePending = false;
    _restoredStartAt = Duration.zero;
    _autoplayRequested = autoplay;
    _loadedPaused = !autoplay;
    _seekDuringLoad = null;
    // A new load owns the network: abort the previous load's probe so it
    // cannot hold this one back.
    _closeLoadProbe();
    _advancing = true;
    _stuckSince = null;
    _cancelFade();
    state = state.copyWith(
      isLoading: true,
      position: startAt > Duration.zero ? startAt : Duration.zero,
    );
    var failed = false;
    var playerBroken = false;
    try {
      // Reuse warm for this id; cancel warm for any other id.
      if (_warmingId == track.id && _warmFuture != null) {
        try {
          await _warmFuture;
        } on _StreamUnavailable {
          rethrow;
        } catch (_) {}
      } else {
        _cancelWarm();
      }

      final uri = await _getTrackUri(track);
      if (token != _loadToken) return;

      // Do not stop() first: that tears down the media foreground service
      // before the next source can play. setAudioSource replaces the item.

      // Warm the remote stream first, then hand ExoPlayer a cache hit. Retry
      // the same track on transient resolver / player errors.
      final remote = _uriIsRemote(uri);
      final attempts = remote ? 3 : 2;
      for (var attempt = 0; attempt < attempts; attempt++) {
        var settingSource = false;
        try {
          if (remote) {
            await _ensureStreamReady(uri, trackId: track.id);
            if (token != _loadToken) return;
            await _awaitPlayerRecreate();
            if (token != _loadToken) return;
            _lastSourceSetTime = DateTime.now();
            _concat = null;
            _windowQueueIndices = [state.index];
            _concatBaseIndex = 0;
            settingSource = true;
            await _player
                .setAudioSource(
                  _audioItem(track, uri),
                  initialPosition: startAt,
                )
                .timeout(_setSourceTimeout);
          } else {
            final window = await _sourceWindow(track, uri, token);
            if (token != _loadToken) return;
            await _awaitPlayerRecreate();
            if (token != _loadToken) return;
            _lastSourceSetTime = DateTime.now();
            _concat = window.source;
            _concatBaseIndex = window.initialIndex;
            settingSource = true;
            await _player
                .setAudioSource(
                  window.source,
                  initialIndex: window.initialIndex,
                  initialPosition: startAt,
                )
                .timeout(_setSourceTimeout);
          }
          settingSource = false;
          if (token != _loadToken) return;
          final pendingSeek = _seekDuringLoad;
          _seekDuringLoad = null;
          if (pendingSeek != null) {
            await _player.seek(pendingSeek);
          } else if (startAt > Duration.zero &&
              _player.position < const Duration(seconds: 2)) {
            await _player.seek(startAt);
          }
          if (token != _loadToken) return;
          // Source is ready — drop the spinner so the scrubber can move even
          // if play() takes another moment.
          state = state.copyWith(isLoading: false);
          if (_autoplayRequested) {
            final started = await _startPlayback(token);
            // Source is ready — do not recreate just because play() failed
            // (common while backgrounded). Resume / tap play can finish it.
            if (!started && !_userPaused) {
              debugPrint('[player] autoplay deferred after source ready');
            }
          } else {
            await _player.setVolume(_baseVolume);
          }
          break;
        } catch (e) {
          debugPrint('[player] load attempt ${attempt + 1}/$attempts: $e');
          if (token != _loadToken) return;
          playerBroken = settingSource;
          // 404 means the resolver already tried its proxies and YouTube
          // refused the video; retrying only makes the user wait longer.
          if (e is _StreamUnavailable || attempt == attempts - 1) rethrow;
          // setAudioSource failures can leave ExoPlayer unable to accept the
          // next source. Retry on a fresh native instance instead of forcing
          // the user to restart the whole app. Network/probe errors leave the
          // player intact, so they only back off.
          if (playerBroken) await _recreatePlayer();
          if (token != _loadToken) return;
          state = state.copyWith(isLoading: true);
          await Future<void>.delayed(
              Duration(milliseconds: 500 * (attempt + 1)));
          if (token != _loadToken) return;
        }
      }

      if (token != _loadToken) return;
      // A recovery reload must not reset the budget, or a stream that keeps
      // breaking would be reloaded forever.
      if (!streamRecovery) _midStreamReloadCount = 0;
      _handlingStreamError = false;
      if (track.id != _advanceFromId) _advanceFromId = null;
      _applyPalette(track);
      await _persistSession();
      if (recordRecent) _recordRecentDeferred(track);
      if (_player.playing) unawaited(_warmNextTrack());
    } catch (e, st) {
      debugPrint('[player] load failed: $e\n$st');
      if (token == _loadToken) {
        if (playerBroken) await _recreatePlayer();
        failed = true;
      }
    } finally {
      if (token == _loadToken) {
        _advancing = false;
        _handlingStreamError = false;
        if (failed) {
          // A silent restore preload must not greet the user with an error.
          state = state.copyWith(
            isLoading: false,
            error: _autoplayRequested ? 'Playback failed' : null,
          );
        } else if (state.isLoading) {
          state = state.copyWith(isLoading: false);
        }
      }
    }
  }

  Future<bool> _waitUntilPlayable(int token) async {
    const timeout = Duration(seconds: 20);
    final ready = {ja.ProcessingState.ready, ja.ProcessingState.buffering};
    if (ready.contains(_player.processingState)) {
      return token == _loadToken;
    }
    try {
      await _player.processingStateStream
          .where(ready.contains)
          .first
          .timeout(timeout);
    } on TimeoutException {
      debugPrint('[player] wait ready timed out');
      return false;
    }
    return token == _loadToken;
  }

  Future<bool> _startPlayback(int token) async {
    // Do not clear _userPaused — pause during load must win over autoplay.
    _cancelFade();
    await _player.setVolume(_baseVolume);
    if (token != _loadToken) return false;
    if (_userPaused) return true;
    final ready = await _waitUntilPlayable(token);
    if (!ready || token != _loadToken) return false;
    if (_userPaused) return true;
    await _player.play();
    if (token != _loadToken) return false;
    if (_userPaused) {
      await _player.pause();
      return true;
    }
    if (!_player.playing) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (token != _loadToken) return false;
      if (_userPaused) return true;
      await _player.play();
      if (_userPaused) {
        await _player.pause();
        return true;
      }
    }
    if (token != _loadToken) return false;
    if (_userPaused) {
      await _player.pause();
      return true;
    }
    if (!_player.playing) return false;
    _fadeIn();
    return true;
  }
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
    unawaited(persistSessionNow());
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
    state = state.copyWith(sleepRemaining: duration, sleepAtTrackEnd: false);
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
  List<Track> _enrichQueue(List<Track> queue) {
    final downloads = {
      for (final t in ref.read(localStoreProvider).downloads()) t.id: t,
    };
    return queue
        .map((track) => downloads[track.id] ?? track)
        .toList(growable: false);
  }

  /// Throttled, not debounced: position ticks arrive every 200 ms, so a
  /// debounce would never fire while a track keeps playing.
  void _schedulePersistSession() {
    if (!ref.read(resumePlaybackProvider)) return;
    if (!state.hasTrack) return;
    if (DateTime.now().difference(_lastPersistAt) < _persistInterval) return;
    unawaited(_persistSession());
  }

  /// Immediate save — used on pause and when the app backgrounds.
  Future<void> persistSessionNow() => _persistSession();

  Future<void> _persistSession() async {
    if (!ref.read(resumePlaybackProvider)) return;
    if (!state.hasTrack || state.queue.isEmpty) return;
    _lastPersistAt = DateTime.now();
    // Right after a pause just_audio's position can still report the value
    // from when the source was set; the polled state.position is accurate.
    final position = _sessionRestorePending
        ? _restoredStartAt
        : (state.isLoading || !_player.playing
            ? state.position
            : _player.position);
    await ref.read(localStoreProvider).savePlaybackSession(
          queue: state.queue,
          index: state.index,
          position: position,
        );
  }

  /// Recents/stats writes trigger a sync push and invalidate several
  /// providers that hit the network; keep that off the critical path of
  /// starting a track, and skip tracks the user skipped right away.
  void _recordRecentDeferred(Track t) {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (state.current?.id == t.id) unawaited(_recordRecent(t));
    });
  }

  Future<void> _recordRecent(Track t) async {
    final store = ref.read(localStoreProvider);
    await store.pushRecent(t);
    await store.bumpPlay(t);
    ref.read(syncServiceProvider).pushStateNow();
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
