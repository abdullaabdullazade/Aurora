import '../entities/track.dart';

/// Domain contract. Presentation depends on this abstraction, never on Dio /
/// youtube_explode directly (Dependency Inversion).
abstract interface class MusicRepository {
  /// Online search (YouTube Music style). [filter] e.g. tracks/videos/albums.
  Future<List<Track>> search(String query, {String filter = 'tracks'});

  Future<List<Track>> trending({bool refresh = false});

  /// Resolver search without extra query shaping.
  Future<List<Track>> searchTracks(String query, {int limit = 25});

  /// YouTube playlist search for Home recommendations (cached like
  /// [searchTracks]).
  Future<List<Track>> searchPlaylists(String query, {int limit = 10});

  /// Global chart tracks from a curated YouTube playlist.
  Future<List<Track>> topCharts();

  /// Clears in-memory recommendation caches (trending / charts).
  void invalidateRecommendationCaches();

  Future<List<Track>> recentlyPlayed();

  /// Resolves a playable stream URL for [track] (audio-only by default).
  Future<Uri> resolveStream(Track track, {bool audioOnly = true});

  /// Locally indexed downloads (offline-first).
  Future<List<Track>> downloads();

  /// Imports a YouTube playlist / album / mix link.
  Future<({String title, List<Track> tracks})> importPlaylist(String url);

  /// Search autocomplete. Returns an empty list rather than throwing — a
  /// suggestion strip must never break typing.
  Future<List<String>> suggest(String query);
}
