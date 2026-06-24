import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Single source of truth for [ThemeData]. Dark only by design.
abstract final class AppTheme {
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.voidBlack,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accentBright,
      surface: AppColors.base,
      onSurface: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.voidBlack,
      textTheme: AppType.build(),
      splashColor: AppColors.accentSoft,
      highlightColor: Colors.transparent,
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        activeTrackColor: AppColors.accentBright,
        inactiveTrackColor: AppColors.glassStroke,
        thumbColor: Colors.white,
        overlayColor: AppColors.accentSoft,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 24),
      snackBarTheme: _snackBar(),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.glassFill,
        side: const BorderSide(color: AppColors.glassStroke),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rPill),
        labelStyle: AppType.build().labelLarge,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _FadeUpTransitionBuilder(),
        TargetPlatform.iOS: _FadeUpTransitionBuilder(),
      }),
    );
  }

  // Light variant. Immersive media screens (player, detail) stay dark by
  // design; this mainly themes the browse surfaces.
  static const Color lightBg = Color(0xFFF3F3F6);
  static const Color lightInk = Color(0xFF0B0C10);
  static const Color lightInk2 = Color(0xFF5B5B62);

  static ThemeData light() {
    final scheme = const ColorScheme.light(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: Colors.white,
      onSurface: lightInk,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: lightBg,
      textTheme: AppType.build().apply(
        bodyColor: lightInk,
        displayColor: lightInk,
      ),
      splashColor: AppColors.accentSoft,
      highlightColor: Colors.transparent,
      iconTheme: const IconThemeData(color: lightInk, size: 24),
      snackBarTheme: _snackBar(),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _FadeUpTransitionBuilder(),
        TargetPlatform.iOS: _FadeUpTransitionBuilder(),
      }),
    );
  }

  // Shared toast style. A dark pill with white text stays readable in both
  // light and dark mode — without an explicit content color the text defaults
  // to a dark on-inverse-surface color and vanishes on the dark background.
  static SnackBarThemeData _snackBar() => SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.elevated,
        contentTextStyle: AppType.build().bodyMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
        actionTextColor: AppColors.accentBright,
        elevation: 8,
        insetPadding: const EdgeInsets.all(Sp.lg),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rPill),
      );
}

/// Soft fade-through + subtle upward slide for route pushes.
class _FadeUpTransitionBuilder extends PageTransitionsBuilder {
  const _FadeUpTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}
