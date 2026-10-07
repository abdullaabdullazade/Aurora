import 'track.dart';

/// Where a quick-access Home playlist came from.
enum RecentPlaylistSource { library, youtube }

/// MRU playlist tile for the Home 2×2 grid (not a full library entity).
class RecentPlaylist {
  final String id;
  final String title;
  final String artworkUrl;
  final RecentPlaylistSource source;
  final String? libraryId;
  final String? browseUrl;
  /// Snapshot for YouTube taps so we can play without a network round-trip.
  final List<Track> tracks;
  final DateTime updatedAt;

  const RecentPlaylist({
    required this.id,
    required this.title,
    required this.artworkUrl,
    required this.source,
    this.libraryId,
    this.browseUrl,
    this.tracks = const [],
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artworkUrl': artworkUrl,
        'source': source.name,
        'libraryId': libraryId,
        'browseUrl': browseUrl,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory RecentPlaylist.fromJson(Map<dynamic, dynamic> j) {
    final sourceName = '${j['source'] ?? 'library'}';
    return RecentPlaylist(
      id: '${j['id']}',
      title: '${j['title'] ?? 'Playlist'}',
      artworkUrl: '${j['artworkUrl'] ?? ''}',
      source: sourceName == 'youtube'
          ? RecentPlaylistSource.youtube
          : RecentPlaylistSource.library,
      libraryId: j['libraryId'] as String?,
      browseUrl: j['browseUrl'] as String?,
      tracks: ((j['tracks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Track.fromJson(Map<dynamic, dynamic>.from(e)))
          .toList(growable: false),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (j['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  factory RecentPlaylist.library({
    required String libraryId,
    required String title,
    required String artworkUrl,
    List<Track> tracks = const [],
  }) =>
      RecentPlaylist(
        id: 'lib:$libraryId',
        title: title,
        artworkUrl: artworkUrl,
        source: RecentPlaylistSource.library,
        libraryId: libraryId,
        tracks: tracks,
        updatedAt: DateTime.now(),
      );

  factory RecentPlaylist.youtube({
    required String browseUrl,
    required String title,
    required String artworkUrl,
    required List<Track> tracks,
  }) =>
      RecentPlaylist(
        // String.hashCode is not guaranteed stable across runs; the URL is.
        id: 'yt:$browseUrl',
        title: title,
        artworkUrl: artworkUrl,
        source: RecentPlaylistSource.youtube,
        browseUrl: browseUrl,
        tracks: tracks,
        updatedAt: DateTime.now(),
      );
}
