/// One synced lyric line. [time] is seconds from track start.
class LyricLine {
  final double time;
  final String text;
  const LyricLine(this.time, this.text);
}

/// Result of a lyric lookup. [synced] is empty when only plain text exists.
class LyricsResult {
  final List<LyricLine> synced;
  final String plain;
  final bool found;
  const LyricsResult({
    this.synced = const [],
    this.plain = '',
    this.found = false,
  });

  bool get isSynced => synced.isNotEmpty;
}
