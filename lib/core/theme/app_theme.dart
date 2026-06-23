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
