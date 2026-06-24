import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'core/db/local_store.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/root_scaffold.dart';
import 'presentation/state/providers.dart';

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

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const AuroraApp(),
    ),
  );
}

class AuroraApp extends StatelessWidget {
  const AuroraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aurora Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const RootScaffold(),
    );
  }
}
