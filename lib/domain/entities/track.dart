import 'package:flutter/painting.dart';

/// Immutable core entity. The Domain layer knows nothing about JSON internals
/// beyond simple (de)serialization for local persistence.
class Track {
  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final Duration duration;
  final int plays;

  /// Dominant color used for ambient backgrounds / glows.
  final Color accent;

  /// True once [accent] came from the artwork itself. Until then it is the
  /// deterministic id-hash colour, which has nothing to do with the cover —
  /// fine for a small glow, wrong for a full-screen wash.
  final bool paletteReady;

  /// Null while streaming-only; set once downloaded to disk.
  final String? localPath;

  /// Uploader/channel page on YouTube (when known from the resolver).
  final String? channelUrl;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.duration,
    this.plays = 0,
    this.accent = const Color(0xFF1DB954),
    this.paletteReady = false,
    this.localPath,
    this.channelUrl,
  });

  bool get isDownloaded => localPath != null;

  Track copyWith({String? localPath, Color? accent, bool? paletteReady}) =>
      Track(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: duration,
        plays: plays,
        accent: accent ?? this.accent,
        paletteReady: paletteReady ?? this.paletteReady,
        localPath: localPath ?? this.localPath,
        channelUrl: channelUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'seconds': duration.inSeconds,
        'plays': plays,
        'accent': accent.toARGB32(),
        'localPath': localPath,
        'channelUrl': channelUrl,
      };

  factory Track.fromJson(Map<dynamic, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String,
        artworkUrl: j['artworkUrl'] as String,
        duration: Duration(seconds: (j['seconds'] as num).toInt()),
        plays: (j['plays'] as num?)?.toInt() ?? 0,
        accent: Color((j['accent'] as num?)?.toInt() ?? 0xFF1DB954),
        localPath: j['localPath'] as String?,
        channelUrl: j['channelUrl'] as String?,
      );

  /// Deterministic vibrant accent derived from the id — gives every YouTube
  /// result a distinct, stable color without sampling the artwork.
  static Color accentFor(String id) {
    const palette = [
      0xFF7C4DFF, 0xFF00E5FF, 0xFFFF6E40, 0xFF1DB954, 0xFFFF4081,
      0xFF18FFB0, 0xFFFFD740, 0xFF536DFE, 0xFFE040FB, 0xFF64FFDA,
    ];
    return Color(palette[id.hashCode.abs() % palette.length]);
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
