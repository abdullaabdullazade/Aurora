import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

ThemeMode _parse(String s) => switch (s) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };

String _str(ThemeMode m) => switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };

/// Persisted app theme mode (defaults to dark — the signature look).
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    ref.watch(syncRevisionProvider);
    return _parse(ref.watch(localStoreProvider).themeMode());
  }

  Future<void> set(ThemeMode mode) async {
    await ref.read(localStoreProvider).setThemeMode(_str(mode));
    state = mode;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
