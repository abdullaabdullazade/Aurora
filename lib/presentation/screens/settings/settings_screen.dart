import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../state/favorites_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../../state/auth_controller.dart';
import 'equalizer_screen.dart';
import 'stats_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final crossfade = ref.watch(crossfadeProvider);
    final seconds = ref.watch(crossfadeSecondsProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(Sp.lg),
        children: [
          const _AccountSection(),
          const SizedBox(height: Sp.xl),
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
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EqualizerScreen())),
          ),
          _Switch(
            icon: Icons.multitrack_audio_rounded,
            title: 'Crossfade',
            subtitle: crossfade
                ? 'Tracks fade out and in over ${seconds}s'
                : 'Tracks change instantly',
            value: crossfade,
            onChanged: (v) => ref.read(crossfadeProvider.notifier).set(v),
          ),
          if (crossfade)
            Padding(
              padding: const EdgeInsets.only(left: 60, right: Sp.sm),
              child: Slider(
                value: seconds.toDouble(),
                min: 2,
                max: 12,
                divisions: 10,
                label: '${seconds}s',
                onChanged: (v) =>
                    ref.read(crossfadeSecondsProvider.notifier).set(v.round()),
              ),
            ),
          const SizedBox(height: Sp.xl),
          Text('Library', style: text.labelLarge),
          const SizedBox(height: Sp.sm),
          _Switch(
            icon: Icons.download_for_offline_outlined,
            title: 'Download liked songs',
            subtitle: 'Keep every song you like available offline',
            value: ref.watch(autoDownloadFavoritesProvider),
            onChanged: (v) async {
              await ref.read(autoDownloadFavoritesProvider.notifier).set(v);
              // Turning it on should also catch up on everything already
              // liked, not just apply from here forward.
              if (v) {
                await ref.read(favoritesProvider.notifier).downloadAllLiked();
              }
            },
          ),
          _Tile(
            icon: Icons.insights_rounded,
            title: 'Listening stats',
            subtitle: 'Top artists, most played, time listened',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          const SizedBox(height: Sp.xl),
          Text('About', style: text.labelLarge),
          const SizedBox(height: Sp.sm),
          _Tile(
            icon: Icons.language_rounded,
            title: 'Project website',
            subtitle: 'Discover Aurora Music on the web',
            onTap: () => _openExternalLink(context, AppConfig.websiteUrl),
          ),
          _Tile(
            icon: Icons.code_rounded,
            title: 'Source code',
            subtitle: 'View the project on GitHub',
            onTap: () => _openExternalLink(context, AppConfig.repositoryUrl),
          ),
          const SizedBox(height: Sp.xl),
          Center(
            child: Text('Aurora Music · v1.0', style: text.labelSmall),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternalLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this link.')),
    );
  }
}

class _Switch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Switch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.accentBright,
      secondary: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            borderRadius: Radii.rSm, gradient: AppColors.accentSweep),
        child: Icon(icon, color: Colors.black),
      ),
      title: Text(title, style: text.titleMedium),
      subtitle: Text(subtitle, style: text.bodyMedium),
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

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final authState = ref.watch(authStateProvider);
    final authController = ref.watch(authControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Account', style: text.labelLarge),
        const SizedBox(height: Sp.sm),
        authState.when(
          data: (user) {
            if (user == null) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      borderRadius: Radii.rSm, color: AppColors.elevated),
                  child: const Icon(Icons.login_rounded, color: Colors.white),
                ),
                title: Text('Sign in with Google', style: text.titleMedium),
                subtitle: Text('Sync your music and playlists',
                    style: text.bodyMedium),
                onTap: () async {
                  try {
                    await authController.signInWithGoogle();
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Google sign-in failed: $error')),
                    );
                  }
                },
              );
            }
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: Radii.rSm,
                  image: user.photoURL != null
                      ? DecorationImage(
                          image: NetworkImage(user.photoURL!),
                          fit: BoxFit.cover)
                      : null,
                  color: AppColors.elevated,
                ),
                child: user.photoURL == null
                    ? const Icon(Icons.person_rounded, color: Colors.white)
                    : null,
              ),
              title: Text(user.displayName ?? 'Signed in',
                  style: text.titleMedium),
              subtitle: Text(user.email ?? '', style: text.bodyMedium),
              trailing: IconButton(
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => authController.signOut(),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }
}
