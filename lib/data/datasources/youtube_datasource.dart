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

  /// Resolves an audio-only stream URL for playback / .m4a export.
  ///
  /// Uses the ANDROID client and prefers the MP4 (m4a / itag 140) stream:
  /// that combination is playable by ExoPlayer with no special User-Agent
  /// (verified HTTP 206), whereas the default webm/opus + browser UA returns
  /// HTTP 403 from the YouTube CDN.
  Future<Uri> audioStreamUrl(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [YoutubeApiClient.android],
    );
    final audios = manifest.audioOnly;
    final mp4 = audios
        .where((a) => a.codec.mimeType.contains('mp4'))
        .toList(growable: false);
    final pool = mp4.isNotEmpty ? mp4 : audios.toList();
    pool.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return pool.first.url;
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
