import 'package:flutter/material.dart';
import '../../domain/entities/track.dart';

/// Seed catalogue so every screen renders beautifully with zero network.
/// Swap for real datasource by switching the repository binding in providers.
abstract final class MockTracks {
  static const _art = 'https://picsum.photos/seed';

  static final List<Track> all = [
    _t('1', 'Midnight Aurora', 'Nova Wren', 0xFF7C4DFF, 214, 12300000),
    _t('2', 'Neon Tides', 'Kasai', 0xFF00E5FF, 198, 8800000),
    _t('3', 'Velvet Static', 'Lume', 0xFFFF6E40, 252, 4200000),
    _t('4', 'Glass Horizon', 'Aeon', 0xFF1DB954, 187, 21000000),
    _t('5', 'Ember Drift', 'Sora', 0xFFFF4081, 233, 1500000),
    _t('6', 'Lunar Bloom', 'Vant', 0xFF18FFB0, 201, 6700000),
    _t('7', 'Soft Machine', 'Halo Park', 0xFFFFD740, 176, 990000),
    _t('8', 'Cobalt Dream', 'Mira', 0xFF536DFE, 245, 3300000),
    _t('9', 'Phantom Signal', 'Eris', 0xFFE040FB, 219, 15600000),
    _t('10', 'Quiet Voltage', 'Noor', 0xFF64FFDA, 263, 740000),
  ];

  static List<Track> get trending => all.take(6).toList();
  static List<Track> get recent => all.reversed.take(6).toList();
  static List<Track> get downloads =>
      all.take(4).map((t) => t.copyWith(localPath: '/storage/${t.id}.m4a')).toList();

  static Track _t(String id, String title, String artist, int color,
          int secs, int plays) =>
      Track(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: '$_art/aurora$id/600/600',
        duration: Duration(seconds: secs),
        plays: plays,
        accent: Color(color),
      );
}
