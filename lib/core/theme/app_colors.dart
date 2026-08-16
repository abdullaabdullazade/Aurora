import 'package:flutter/material.dart';
import 'dynamic_palette.dart';

/// Central palette for the "Soft Dark / Glass" aesthetic.
/// Rich blacks + emerald accent + muted greys.
abstract final class AppColors {
  // --- Base backgrounds ---------------------------------------------------
  static const Color voidBlack = Color(0xFF0B0C10); // deepest layer
  static const Color base = Color(0xFF121212); // primary surface
  static const Color elevated = Color(0xFF181818); // cards
  static const Color elevatedHi = Color(0xFF242424); // hovered/active cards

  // --- Accent (emerald / neon) -------------------------------------------
  static const Color accent = Color(0xFF1DB954); // Spotify green
  static const Color accentBright = Color(0xFF00E676); // neon highlight
  static const Color accentSoft = Color(0x331DB954); // 20% glow fill

  // --- Text ---------------------------------------------------------------
  // Ratios are against the darkest surface: primary 19:1, secondary 7.1:1,
  // tertiary 4.6:1. The old tertiary (#6E6E6E) could not clear 4.5:1 against
  // pure black at any size, so it was unreadable by construction.
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textTertiary = Color(0xFF9A9A9A);

  // --- Glass / strokes ----------------------------------------------------
  static const Color glassFill = Color(0x14FFFFFF); // white @ 8%
  static const Color glassStroke = Color(0x1AFFFFFF); // white10
  static const Color scrim = Color(0xCC000000);

  // --- Gradients ----------------------------------------------------------
  /// Ambient radial used behind whole screens.
  static const RadialGradient ambient = RadialGradient(
    center: Alignment(-0.6, -0.9),
    radius: 1.4,
    colors: [Color(0xFF1B2A22), voidBlack],
    stops: [0.0, 0.75],
  );

  /// Accent capsule (play buttons, active pills).
  static const LinearGradient accentSweep = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentBright, accent],
  );

  /// [accentSweep] in an arbitrary track accent, so the play button belongs to
  /// the artwork instead of staying fixed Spotify-green next to a mint UI.
  static LinearGradient accentSweepOf(Color seed) {
    final c = Tone.accent(seed);
    final hsl = HSLColor.fromColor(c);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        hsl.withLightness((hsl.lightness + 0.10).clamp(0.0, 1.0)).toColor(),
        c,
      ],
    );
  }

  /// Full-screen wash behind player-style screens.
  ///
  /// The seed is *not* painted directly: a vivid mid-tone at high alpha is what
  /// made every grey label vanish. It is converted to a deep same-hue backdrop
  /// ([Tone.backdrop]) and laid down nearly opaque, so text contrast no longer
  /// depends on how bright the cover art happens to be.
  static LinearGradient artVeil(Color seed) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Tone.backdropHi(seed).withValues(alpha: 0.90),
          Tone.backdrop(seed).withValues(alpha: 0.94),
          // Foot of the veil keeps the hue instead of collapsing to black —
          // ending on voidBlack cut a hard dark band across the transport row.
          Tone.backdropLo(seed).withValues(alpha: 0.97),
        ],
        stops: const [0.0, 0.55, 1.0],
      );

  /// Header wash for album / playlist / artist tops — same reasoning as
  /// [artVeil], shorter fade because it only covers the app-bar area.
  static LinearGradient artHeader(Color seed) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Tone.backdropHi(seed), voidBlack],
      );
}
