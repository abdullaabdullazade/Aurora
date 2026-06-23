import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../domain/entities/track.dart';

/// Real online datasource. Wire this into a `YoutubeMusicRepository` to replace
/// [MockMusicRepository] in production. Kept thin: pure I/O, no UI concerns.
class YoutubeDatasource {
  final YoutubeExplode _yt;
  YoutubeDatasource([YoutubeExplode? yt]) : _yt = yt ?? YoutubeExplode();

  /// Debounced search should happen in the BLoC/Notifier, not here.
  Future<List<Track>> search(String query) async {
    final results = await _yt.search.search(query);
    return results.map(_toTrack).toList(growable: false);
  }

  /// Highest-bitrate audio-only stream — ideal for .m4a extraction.
  Future<Uri> audioStreamUrl(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    final audio = manifest.audioOnly.withHighestBitrate();
    return audio.url;
  }

  Track _toTrack(Video v) => Track(
        id: v.id.value,
        title: v.title,
        artist: v.author,
        artworkUrl: v.thumbnails.highResUrl,
        duration: v.duration ?? Duration.zero,
        plays: v.engagement.viewCount,
      );

  void dispose() => _yt.close();
}
