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

  /// Songs like [videoId] — YouTube's own Mix for it (same artist first,
  /// then similar artists and genre).
  Future<List<Track>> related(String videoId, {int limit = 25});

  /// A country's Top 100 Songs (YouTube Music Charts).
  Future<List<Track>> chart(String country, {int limit = 50});

  /// The artist's latest uploads from their own channel, newest first.
  Future<List<Track>> newFrom(String artist, {int limit = 4});

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
