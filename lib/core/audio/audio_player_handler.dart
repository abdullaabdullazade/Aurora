import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// OS-level background playback: lock screen, notification tray, headset keys.
///
/// Boot once in main():
/// ```dart
//   config: const AudioServiceConfig(
///     androidNotificationChannelId: 'com.aurora.music.audio',
///     androidNotificationChannelName: 'Aurora Playback',
///     androidNotificationOngoing: true,
///   ),
/// );
/// ```
class AudioPlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  AudioPlayerHandler() {
    _player.playbackEventStream.map(_transform).pipe(playbackState);
  }

  Future<void> setQueue(List<MediaItem> items, List<Uri> urls) async {
    queue.add(items);
    await _player.setAudioSource(
      ConcatenatingAudioSource(
        children: [for (final u in urls) AudioSource.uri(u)],
      ),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  PlaybackState _transform(PlaybackEvent event) {
    final playing = _player.playing;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
