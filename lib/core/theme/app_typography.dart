import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Typographic scale. Tight, high-contrast, sans-serif (Plus Jakarta Sans).
abstract final class AppType {
  static TextTheme build() {
    final base = GoogleFonts.plusJakartaSansTextTheme();
    return base.copyWith(
      displayLarge: _t(base.displayLarge, 34, FontWeight.w800, -0.5),
      headlineMedium: _t(base.headlineMedium, 24, FontWeight.w700, -0.3),
      titleLarge: _t(base.titleLarge, 19, FontWeight.w700, -0.2),
      titleMedium: _t(base.titleMedium, 15, FontWeight.w600, 0),
      bodyLarge: _t(base.bodyLarge, 15, FontWeight.w500, 0,
          color: AppColors.textPrimary),
      bodyMedium: _t(base.bodyMedium, 13, FontWeight.w500, 0.1,
          color: AppColors.textSecondary),
      labelLarge: _t(base.labelLarge, 13, FontWeight.w700, 0.4),
      labelSmall: _t(base.labelSmall, 11, FontWeight.w600, 0.8,
          color: AppColors.textTertiary),
    );
  }

  static TextStyle _t(
    TextStyle? src,
    double size,
    FontWeight weight,
    double spacing, {
    Color color = AppColors.textPrimary,
  }) =>
      (src ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color,
        height: 1.2,
      );
}
