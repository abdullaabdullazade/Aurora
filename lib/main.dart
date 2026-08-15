import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'core/config/app_config.dart';
import 'core/db/local_store.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/root_scaffold.dart';
import 'presentation/state/providers.dart';
import 'presentation/state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay);
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp]);

  // Background playback: media notification + lock-screen + headset controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.aurora.music.channel.audio',
    androidNotificationChannelName: 'Aurora playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  final store = LocalStore();
  await store.init();

  // Resolve the backend URL from the always-on Vercel registry (the LAN IP
  // changes); fall back to the hardcoded AppConfig.apiBase if unreachable.
  await _resolveBackend();

  // Engagement notifications (daily nudges). Best-effort — never block boot.
  try {
    await NotificationService.instance.init();
    await NotificationService.instance.scheduleDailyNudges();
  } catch (_) {/* notifications optional */}

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const AuroraApp(),
    ),
  );
}

Future<void> _resolveBackend() async {
  // Local dev pins the backend by hand — a registry hit would point the app at
  // the remote tunnel and silently ignore the server running on this machine.
  if (AppConfig.useLocalServer) return;
  try {
    final res = await Dio()
        .get('${AppConfig.registryUrl}/api/server')
        .timeout(const Duration(seconds: 5));
    final url = (res.data as Map)['url'];
    if (url is String && url.startsWith('http')) AppConfig.apiBase = url;
  } catch (_) {/* keep LAN fallback */}
}

class AuroraApp extends ConsumerWidget {
  const AuroraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Aurora Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: const RootScaffold(),
    );
  }
}
