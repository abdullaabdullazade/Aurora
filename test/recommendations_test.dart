import 'dart:ui';

import 'package:aurora_music/domain/entities/track.dart';
import 'package:aurora_music/domain/services/recommendations.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String id, String artist) => Track(
      id: id,
      title: 'Song $id',
      artist: artist,
      artworkUrl: '',
      duration: const Duration(minutes: 3),
      accent: const Color(0xFF000000),
    );

void main() {
  test('artist spellings collapse to one key', () {
    expect(artistKey('EminemMusic'), artistKey('Eminem'));
    expect(artistKey('Eminem - Topic'), artistKey('Eminem'));
    expect(artistKey('EminemVEVO'), artistKey('Eminem'));
    expect(artistKey('Ati242'), isNot(artistKey('Ezhel')));
  });

  test('seeds are distinct artists, recent first, YouTube only', () {
    final seeds = pickSeeds(
      recent: [
        _t('aaaaaaaaaaa', 'Ati242'),
        _t('bbbbbbbbbbb', 'Ati242'),
        _t('12345', 'Local file'),
        _t('ccccccccccc', 'Ezhel'),
      ],
      mostPlayed: [_t('ddddddddddd', 'EminemMusic'), _t('eeeeeeeeeee', 'Eminem')],
      liked: const [],
    );
    expect(seeds.map((s) => s.id), ['aaaaaaaaaaa', 'ccccccccccc', 'ddddddddddd']);
  });

  test('blend interleaves mixes, skips known songs, caps artists', () {
    final rap = [
      _t('r1xxxxxxxxx', 'Ati242'),
      _t('r2xxxxxxxxx', 'Ati242'),
      _t('r3xxxxxxxxx', 'Ati242'),
      _t('r4xxxxxxxxx', 'Ezhel'),
    ];
    final eminem = [
      _t('e1xxxxxxxxx', 'EminemMusic'),
      _t('e2xxxxxxxxx', '50 Cent'),
    ];
    final picks = blendRecommendations(
      [rap, eminem],
      exclude: {'r1xxxxxxxxx'},
      perArtist: 2,
    );
    expect(picks.map((t) => t.id),
        ['e1xxxxxxxxx', 'r2xxxxxxxxx', 'e2xxxxxxxxx', 'r3xxxxxxxxx', 'r4xxxxxxxxx']);
  });

  test('chart country follows the alphabet of what is played', () {
    expect(
        guessChartCountry([
          _t('a', 'Ati242').copyWith(),
          Track(id: 'b', title: 'Sönen Sigaralar', artist: 'Ati242',
              artworkUrl: '', duration: Duration.zero,
              accent: const Color(0xFF000000)),
          Track(id: 'c', title: 'Şehrimin Tadı', artist: 'Ezhel',
              artworkUrl: '', duration: Duration.zero,
              accent: const Color(0xFF000000)),
        ]),
        'Turkey');
    expect(
        guessChartCountry([
          Track(id: 'd', title: 'Gəl', artist: 'Aygün', artworkUrl: '',
              duration: Duration.zero, accent: const Color(0xFF000000)),
          Track(id: 'e', title: 'Sənsiz', artist: 'X', artworkUrl: '',
              duration: Duration.zero, accent: const Color(0xFF000000)),
        ]),
        'Azerbaijan');
    expect(guessChartCountry([_t('f', 'Eminem'), _t('g', '50 Cent')]), isNull);
  });

  test('distinct artists keep order and merge spellings', () {
    expect(
        distinctArtists([
          _t('a', 'Ezhel'),
          _t('b', 'EzhelVEVO'),
          _t('c', 'Ati242'),
          _t('d', 'Unknown'),
          _t('e', 'S.O.S and 2 more'),
        ]),
        ['Ezhel', 'Ati242', 'S.O.S']);
  });
}
