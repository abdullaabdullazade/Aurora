import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../widgets/glass.dart';
import '../../state/player_controller.dart';

/// Synced lyrics panel. Highlights the active line based on playback position.
class LyricsSheet extends ConsumerWidget {
  const LyricsSheet({super.key});

  // (timestampSeconds, line)
  static const _lines = <(int, String)>[
    (0, 'City lights bleed into the dark'),
    (8, 'I chase the hum of a neon heart'),
    (16, 'We were static, we were sound'),
    (24, 'Falling up while the world spins down'),
    (32, 'Midnight aurora, paint the sky'),
    (40, 'Every color says goodbye'),
    (48, 'Hold the silence, let it bloom'),
    (56, 'Echoes dancing in the room'),
    (64, 'Midnight aurora, carry me'),
    (72, 'Into everything we’ll be'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(playerControllerProvider).position.inSeconds;
    final text = Theme.of(context).textTheme;

    int activeIndex = 0;
    for (var i = 0; i < _lines.length; i++) {
      if (pos >= _lines[i].$1) activeIndex = i;
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Glass(
        radius: const BorderRadius.vertical(top: Radii.xl),
        blur: 30,
        opacity: 0.16,
        child: Column(
          children: [
            const SizedBox(height: Sp.md),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.glassStroke, borderRadius: Radii.rPill),
            ),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Text('Lyrics', style: text.titleLarge),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.xxxl),
                itemCount: _lines.length,
                itemBuilder: (_, i) {
                  final active = i == activeIndex;
                  return AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: text.titleLarge!.copyWith(
                      fontSize: 22,
                      height: 1.7,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
                      child: Text(_lines[i].$2),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
