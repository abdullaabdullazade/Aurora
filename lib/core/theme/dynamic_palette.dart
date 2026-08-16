import 'package:flutter/painting.dart';

/// Artwork-derived color math.
///
/// A color sampled from cover art has to fill two roles that pull in opposite
/// directions: a **mark** color (icons, glows, progress) wants to be vivid and
/// mid-lightness, while a **surface** color (the full-screen veil behind the
/// title, artist and controls) has to be dark enough that the grey labels drawn
/// on it keep their contrast. Using one color for both is what turned the
/// player into a bright wash with unreadable secondary text.
///
/// [Tone] splits the roles and keeps both sides on the WCAG 2.1 ratios:
/// 4.5:1 for normal text, 3:1 for large text and non-text UI marks.
abstract final class Tone {
  /// Reference surface used when checking a mark against the darkest layer.
  static const Color _void = Color(0xFF0B0C10);

  /// Dimmest label the app draws on an artwork surface. Backdrops are darkened
  /// until even this one clears 4.5:1.
  static const Color _dimmestLabel = Color(0xFF9A9A9A);

  /// WCAG 2.1 contrast ratio (1.0 – 21.0) between two opaque colors.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Composite [fg] over [bg] at [fg]'s alpha — the color a viewer actually
  /// sees through a translucent veil, which is what contrast must be judged on.
  static Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

  /// Vivid mark color derived from a raw sampled color.
  ///
  /// Saturation and lightness are pulled into a band that reads as an accent
  /// (very dark or washed-out samples become useless as marks), then lightened
  /// until it clears 3:1 against the darkest surface — the WCAG minimum for
  /// non-text UI components.
  static Color accent(Color raw, {Color on = _void}) {
    final hsl = HSLColor.fromColor(raw);
    final base = hsl
        .withSaturation(hsl.saturation.clamp(0.45, 0.92))
        .withLightness(hsl.lightness.clamp(0.50, 0.66));

    var l = base.lightness;
    var out = base.toColor();
    while (contrast(out, on) < 3.0 && l < 0.86) {
      l += 0.03;
      out = base.withLightness(l).toColor();
    }
    return out;
  }

  /// Deep, desaturated tint of the same hue — the color screens are washed in.
  ///
  /// The hue survives (so the screen still "belongs" to the artwork) but the
  /// lightness is driven down until the dimmest label the app draws still
  /// clears 4.5:1 on it.
  static Color backdrop(Color source, {double lightness = 0.15}) {
    final hsl = HSLColor.fromColor(source);
    final base =
        hsl.withSaturation((hsl.saturation * 0.55).clamp(0.14, 0.42));

    var l = lightness;
    var out = base.withLightness(l).toColor();
    while (contrast(_dimmestLabel, out) < 4.5 && l > 0.04) {
      l -= 0.01;
      out = base.withLightness(l).toColor();
    }
    return out;
  }

  /// Black or white — whichever reads better on [bg]. A fixed black glyph on a
  /// dynamic accent goes muddy the moment the artwork yields a deep hue.
  static Color onColor(Color bg) =>
      contrast(const Color(0xFF000000), bg) >= contrast(const Color(0xFFFFFFFF), bg)
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF);

  /// Same hue as [backdrop] but a step darker — the foot of a veil. Fading to
  /// pure black instead left a visible grey-to-black seam across the controls.
  static Color backdropLo(Color source) {
    final b = HSLColor.fromColor(backdrop(source));
    return b.withLightness((b.lightness - 0.06).clamp(0.0, 1.0)).toColor();
  }

  /// Same hue as [backdrop] but a step lighter — used for the top of a veil so
  /// the wash has depth instead of reading as one flat rectangle.
  static Color backdropHi(Color source) {
    final b = HSLColor.fromColor(backdrop(source));
    return b.withLightness((b.lightness + 0.06).clamp(0.0, 1.0)).toColor();
  }
}
