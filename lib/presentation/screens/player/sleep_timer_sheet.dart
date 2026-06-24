import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../state/player_controller.dart';
import '../../widgets/glass.dart';

class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => const SleepTimerSheet(),
      );

  static const _options = [5, 10, 15, 30, 45, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining =
        ref.watch(playerControllerProvider.select((s) => s.sleepRemaining));
    final ctrl = ref.read(playerControllerProvider.notifier);
    final text = Theme.of(context).textTheme;

    return Glass(
      radius: const BorderRadius.vertical(top: Radii.xl),
      blur: 30,
      opacity: 0.16,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Sp.md),
            Container(
                width: 44,
                height: 4,
                decoration: const BoxDecoration(
                    color: AppColors.glassStroke, borderRadius: Radii.rPill)),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Row(
                children: [
                  const Icon(Icons.bedtime_rounded,
                      color: AppColors.accentBright),
                  const SizedBox(width: Sp.sm),
                  Text('Sleep timer', style: text.titleLarge),
                  const Spacer(),
                  if (remaining != null)
                    Text(Fmt.duration(remaining),
                        style: text.titleMedium
                            ?.copyWith(color: AppColors.accentBright)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final m in _options)
                    _Chip(
                      label: '$m min',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ctrl.setSleep(Duration(minutes: m));
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: Sp.lg),
            if (remaining != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.glassStroke),
                      padding: const EdgeInsets.symmetric(vertical: Sp.md),
                    ),
                    onPressed: () {
                      ctrl.setSleep(null);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Turn off timer'),
                  ),
                ),
              ),
            const SizedBox(height: Sp.sm),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.lg),
              child: Text(
                'Audio fades out smoothly over the last 10 seconds.',
                textAlign: TextAlign.center,
                style: text.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
        decoration: BoxDecoration(
          borderRadius: Radii.rPill,
          color: AppColors.glassFill,
          border: Border.all(color: AppColors.glassStroke),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }
}
