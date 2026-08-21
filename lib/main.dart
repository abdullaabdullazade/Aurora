import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/config/app_config.dart';
import 'core/db/local_store.dart';
import 'core/db/sync_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/root_scaffold.dart';
import 'presentation/state/providers.dart';
import 'presentation/state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
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
  if (AppConfig.useLocalServer) return;
  // We skip Vercel registry entirely because it points to a broken server.
  // The app will now use `AppConfig.apiBase` which is populated from the environment (.env or CLI arguments).
}

class AuroraApp extends ConsumerWidget {
  const AuroraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize SyncService
    ref.read(syncServiceProvider);
    
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
