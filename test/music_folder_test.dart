import 'dart:ui';

import 'package:aurora_music/core/downloads/music_folder.dart';
import 'package:aurora_music/domain/entities/track.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String id, String artist, String title) => Track(
      id: id,
      title: title,
      artist: artist,
      artworkUrl: '',
      duration: Duration.zero,
      accent: const Color(0xFF000000),
    );

void main() {
  test('file name round-trips id, artist and title', () {
    final name = musicFileName(_t('-gbJopcRj2A', 'Ati242', 'Her Nerdeysen'));
    expect(name, 'Ati242 - Her Nerdeysen [-gbJopcRj2A].m4a');
    final parsed = parseMusicFileName(name)!;
    expect(parsed.id, '-gbJopcRj2A');
    expect(parsed.artist, 'Ati242');
    expect(parsed.title, 'Her Nerdeysen');
  });

  test('unsafe characters are replaced, MediaStore clash suffix is read', () {
    final name = musicFileName(_t('abcdefghijk', 'AC/DC', 'Back: in "Black"'));
    expect(name, 'AC_DC - Back_ in _Black_ [abcdefghijk].m4a');
    expect(parseMusicFileName('AC_DC - Back [abcdefghijk] (1).m4a')!.id,
        'abcdefghijk');
  });

  test('other files are ignored', () {
    expect(parseMusicFileName('Some song.mp3'), isNull);
    expect(parseMusicFileName('Song [tooshort].m4a'), isNull);
  });

  test('shared paths are told apart from app storage', () {
    expect(isSharedMediaPath('content://media/external/audio/media/12'), isTrue);
    expect(isSharedMediaPath('/storage/emulated/0/Music/Aurora/x.m4a'), isTrue);
    expect(isSharedMediaPath('/data/user/0/com.aurora.music/app_flutter/aurora/x.m4a'),
        isFalse);
  });
}
