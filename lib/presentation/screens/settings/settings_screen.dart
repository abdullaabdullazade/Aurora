import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../state/settings_controller.dart';
import 'equalizer_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(Sp.lg),
        children: [
          Text('Appearance', style: text.labelLarge),
          const SizedBox(height: Sp.sm),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded),
                  label: Text('Light')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded),
                  label: Text('Dark')),
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_rounded),
                  label: Text('Auto')),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: Sp.xl),
          Text('Audio', style: text.labelLarge),
          const SizedBox(height: Sp.sm),
          _Tile(
            icon: Icons.equalizer_rounded,
            title: 'Equalizer',
            subtitle: 'Tune the sound across 5 bands',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const EqualizerScreen())),
          ),
          const SizedBox(height: Sp.xl),
          Center(
            child: Text('Aurora Music · v1.0', style: text.labelSmall),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Tile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            borderRadius: Radii.rSm, gradient: AppColors.accentSweep),
        child: Icon(icon, color: Colors.black),
      ),
      title: Text(title, style: text.titleMedium),
      subtitle: Text(subtitle, style: text.bodyMedium),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
