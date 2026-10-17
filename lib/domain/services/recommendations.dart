import '../entities/track.dart';

/// Pure helpers behind "For you": pick a few songs that describe the
/// listener's taste, then blend YouTube's Mix for each of them.

/// YouTube video ids; device (MediaStore) rows have short numeric ids and
/// have no Mix.
bool isYoutubeId(String id) =>
    RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) && int.tryParse(id) == null;

/// "EminemMusic", "Eminem - Topic", "EminemVEVO" -> "eminem", so one artist
/// is not counted as three when capping how often they appear.
String artistKey(String artist) {
  var a = artist.toLowerCase().trim();
  a = a.replaceAll(RegExp(r'\s*-\s*topic$'), '');
  a = a.replaceAll(RegExp(r'(vevo|official|music|tv)$'), '');
  return a.replaceAll(RegExp(r'[^a-z0-9À-ɏЀ-ӿ]'), '');
}

/// Up to [count] seeds with different artists: the most recent listens
/// first (what you are into now), then the most played (what you always
/// come back to). [recent] is newest first; [mostPlayed] is ranked.
List<Track> pickSeeds({
  required List<Track> recent,
  required List<Track> mostPlayed,
  required List<Track> liked,
  int count = 5,
}) {
  final seeds = <Track>[];
  final artists = <String>{};
  void take(Iterable<Track> source, int upTo) {
    for (final t in source) {
      if (seeds.length >= upTo) return;
      if (!isYoutubeId(t.id)) continue;
      if (!artists.add(artistKey(t.artist))) continue;
      seeds.add(t);
    }
  }

  take(recent, 3);
  take(mostPlayed, count);
  take(liked, count); // a listener with likes but little history
  return seeds;
}

/// Round-robin over the seed Mixes so every taste is represented, skipping
/// songs the listener already knows ([exclude]) and capping each artist at
/// [perArtist] so one artist's Mix cannot fill the whole row.
List<Track> blendRecommendations(
  List<List<Track>> mixes, {
  Set<String> exclude = const {},
  int perArtist = 2,
  int limit = 30,
}) {
  final out = <Track>[];
  final seen = <String>{...exclude};
  final perArtistCount = <String, int>{};
  final longest = mixes.fold<int>(0, (m, l) => l.length > m ? l.length : m);
  for (var i = 0; i < longest && out.length < limit; i++) {
    for (final mix in mixes) {
      if (i >= mix.length || out.length >= limit) continue;
      final t = mix[i];
      if (!seen.add(t.id)) continue;
      final key = artistKey(t.artist);
      final n = perArtistCount[key] ?? 0;
      if (n >= perArtist) continue;
      perArtistCount[key] = n + 1;
      out.add(t);
    }
  }
  return out;
}

/// Which country's chart fits what the listener plays, judged by the
/// alphabet of their most played titles/artists: Azerbaijani "ə",
/// Turkish "ı/ğ/ş/İ" (or "ö/ü/ç" without German "ä/ß"), Cyrillic. Null means no clear signal (use Global).
/// A country needs at least two tracks and a quarter of the sample.
String? guessChartCountry(List<Track> mostPlayed) {
  final votes = <String, int>{};
  for (final t in mostPlayed) {
    final text = '${t.title} ${t.artist}';
    final String? country;
    if (text.contains(RegExp(r'[əƏ]'))) {
      country = 'Azerbaijan';
    } else if (text.contains(RegExp(r'[ıİğĞşŞ]')) ||
        // ö/ü/ç are Turkish too, but German shares ö/ü; ä/ß mark German.
        (text.contains(RegExp(r'[öÖüÜçÇ]')) &&
            !text.contains(RegExp(r'[äÄß]')))) {
      country = 'Turkey';
    } else if (text.contains(RegExp(r'[\u0400-\u04FF]'))) {
      country = 'Russia';
    } else {
      country = null;
    }
    if (country != null) votes[country] = (votes[country] ?? 0) + 1;
  }
  if (votes.isEmpty) return null;
  final best = votes.entries.reduce((a, b) => a.value >= b.value ? a : b);
  if (best.value < 2 || best.value * 4 < mostPlayed.length) return null;
  return best.key;
}

/// Distinct artists in order of first appearance, by [artistKey].
List<String> distinctArtists(Iterable<Track> tracks, {int limit = 6}) {
  final out = <String>[];
  final seen = <String>{};
  for (final t in tracks) {
    if (out.length >= limit) break;
    final name = t.artist.trim();
    if (name.isEmpty || name == 'Unknown') continue;
    if (seen.add(artistKey(name))) out.add(name);
  }
  return out;
}
