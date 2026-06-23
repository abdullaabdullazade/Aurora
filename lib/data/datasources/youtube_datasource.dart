import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../domain/entities/track.dart';

/// Real online datasource backed by youtube_explode_dart. Pure I/O.
class YoutubeDatasource {
  final YoutubeExplode _yt;
  YoutubeDatasource([YoutubeExplode? yt]) : _yt = yt ?? YoutubeExplode();

  /// Search videos and map to [Track]s. Filters out live streams and clips
  /// without a duration so the queue stays clean.
  Future<List<Track>> search(String query) async {
    final results = await _yt.search.search(query);
    return results
        .where((v) => v.duration != null && v.duration! > Duration.zero)
        .map(_toTrack)
        .toList(growable: false);
  }

  /// Highest-bitrate audio-only stream URL — used for playback + .m4a export.
  Future<Uri> audioStreamUrl(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    return manifest.audioOnly.withHighestBitrate().url;
  }

  Track _toTrack(Video v) => Track(
        id: v.id.value,
        title: v.title,
        artist: v.author,
        artworkUrl: v.thumbnails.highResUrl,
        duration: v.duration ?? Duration.zero,
        plays: v.engagement.viewCount,
        accent: Track.accentFor(v.id.value),
      );

  void dispose() => _yt.close();
}
