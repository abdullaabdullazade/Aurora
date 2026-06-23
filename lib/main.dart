import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/root_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay);
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp]);

  // To go live, boot audio_service + Hive here, then override the repository
  // provider with the real implementation.
  runApp(const ProviderScope(child: AuroraApp()));
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
