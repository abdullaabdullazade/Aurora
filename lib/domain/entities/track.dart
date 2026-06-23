import 'package:flutter/painting.dart';

/// Immutable core entity. The Domain layer knows nothing about JSON, Hive,
/// or YouTube — only this shape.
class Track {
  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final Duration duration;
  final int plays;

  /// Dominant color sampled from artwork — drives ambient backgrounds.
  final Color accent;

  /// Null while streaming-only; set once downloaded to disk.
  final String? localPath;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.duration,
    this.plays = 0,
    this.accent = const Color(0xFF1DB954),
    this.localPath,
  });

  bool get isDownloaded => localPath != null;

  Track copyWith({String? localPath}) => Track(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: duration,
        plays: plays,
        accent: accent,
        localPath: localPath ?? this.localPath,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
