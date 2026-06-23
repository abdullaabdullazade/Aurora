import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass.dart';
import '../../state/player_controller.dart';

/// Up-next queue with drag-and-drop reordering.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
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
                color: AppColors.glassStroke,
                borderRadius: Radii.rPill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Row(
                children: [
                  Text('Up Next', style: text.titleLarge),
                  const Spacer(),
                  Text('${state.queue.length} tracks',
                      style: text.labelSmall),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: scroll,
                padding: const EdgeInsets.fromLTRB(Sp.sm, 0, Sp.sm, Sp.xxl),
                itemCount: state.queue.length,
                onReorder: ctrl.reorderQueue,
                proxyDecorator: (child, _, __) => Material(
                  color: Colors.transparent,
                  child: child,
                ),
                itemBuilder: (context, i) {
                  final t = state.queue[i];
                  final active = i == state.index;
                  return Padding(
                    key: ValueKey(t.id),
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.sm, vertical: Sp.xs),
                    child: Row(
                      children: [
                        Artwork(track: t, size: 46, radius: Radii.rSm),
                        const SizedBox(width: Sp.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleMedium?.copyWith(
                                    color: active
                                        ? AppColors.accentBright
                                        : AppColors.textPrimary,
                                  )),
                              Text(t.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium),
                            ],
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle_rounded,
                              color: AppColors.textSecondary),
                        ),
                      ],
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
