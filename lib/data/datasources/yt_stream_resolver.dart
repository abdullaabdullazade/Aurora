import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Headers required to play a googlevideo URL fetched with the ANDROID client:
/// `identity` encoding + a matching YouTube-Android UA, else the CDN 403s.
const ytStreamHeaders = {
  'Accept-Encoding': 'identity',
  'User-Agent':
      'com.google.android.youtube/19.09.37 (Linux; U; Android 14) gzip',
};

/// Resolves a playable audio URL on-device. The phone's residential IP is not
/// hit by the datacenter PO-token block, so this works where a cloud server
/// can't.
class YtStreamResolver {
  final YoutubeExplode _yt;
  YtStreamResolver([YoutubeExplode? yt]) : _yt = yt ?? YoutubeExplode();

  Future<Uri> audioUrl(String videoId) async {
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

  void dispose() => _yt.close();
}
