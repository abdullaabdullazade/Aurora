import 'package:flutter/material.dart';

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
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textTertiary = Color(0xFF6E6E6E);

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

  /// Builds a vertical fade from a dominant art color into the void.
  static LinearGradient artVeil(Color dominant) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          dominant.withValues(alpha: 0.85),
          dominant.withValues(alpha: 0.30),
          voidBlack,
        ],
        stops: const [0.0, 0.45, 1.0],
      );
}
