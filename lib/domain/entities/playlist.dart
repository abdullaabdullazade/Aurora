import 'track.dart';

/// User-created collection of tracks. Persisted locally.
class Playlist {
  final String id;
  final String name;
  final List<Track> tracks;

  const Playlist({
    required this.id,
    required this.name,
    this.tracks = const [],
  });

  String? get coverUrl => tracks.isEmpty ? null : tracks.first.artworkUrl;
  Duration get total =>
      tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

  Playlist copyWith({String? name, List<Track>? tracks}) => Playlist(
        id: id,
        name: name ?? this.name,
        tracks: tracks ?? this.tracks,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<dynamic, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String,
        tracks: ((j['tracks'] as List?) ?? [])
            .map((e) => Track.fromJson(e as Map))
            .toList(),
      );
}
