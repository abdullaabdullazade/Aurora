import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../widgets/glass.dart';
import '../../state/lyrics_controller.dart';
import '../../state/player_controller.dart';

/// Real synced lyrics (lrclib via resolver). Highlights + auto-scrolls the
/// active line; tap a line to seek to it. Falls back to plain text, then to a
/// graceful empty state.
class LyricsSheet extends ConsumerStatefulWidget {
  const LyricsSheet({super.key});
  @override
  ConsumerState<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends ConsumerState<LyricsSheet> {
  final _scroll = ScrollController();
  int _active = -1;
  DateTime? _userScrolledAt; // suspend auto-scroll after a manual scroll

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(int index, int count) {
    if (!_scroll.hasClients || index < 0) return;
    // Don't yank the view while the user is reading/scrolling manually.
    final last = _userScrolledAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 6)) {
      return;
    }
    // Roughly center the active line.
    final target = (index * 46.0) - 160;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(lyricsProvider);
    final posSec =
        ref.watch(playerControllerProvider.select((s) => s.position)).inMilliseconds /
            1000.0;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, sheetScroll) => Glass(
        radius: const BorderRadius.vertical(top: Radii.xl),
        blur: 32,
        opacity: 0.16,
        child: Column(
          children: [
            const SizedBox(height: Sp.md),
            Container(
                width: 44,
                height: 4,
                decoration: const BoxDecoration(
                    color: AppColors.glassStroke, borderRadius: Radii.rPill)),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Row(children: [
                Text('Lyrics', style: text.titleLarge),
                const Spacer(),
                lyrics.maybeWhen(
                  data: (r) => r.isSynced
                      ? Row(children: [
                          const Icon(Icons.graphic_eq_rounded,
                              size: 14, color: AppColors.accentBright),
                          const SizedBox(width: 4),
                          Text('Synced', style: text.labelSmall),
                        ])
                      : const SizedBox.shrink(),
                  orElse: () => const SizedBox.shrink(),
                ),
              ]),
            ),
            Expanded(
              child: lyrics.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accentBright)),
                error: (_, __) => _Empty(text: text),
                data: (r) {
                  if (!r.found) return _Empty(text: text);
                  if (!r.isSynced) {
                    // Plain text fallback.
                    return SingleChildScrollView(
                      controller: sheetScroll,
                      padding: const EdgeInsets.fromLTRB(
                          Sp.xl, 0, Sp.xl, Sp.xxxl),
                      child: Text(r.plain,
                          style: text.titleMedium?.copyWith(
                              height: 1.8, color: AppColors.textSecondary)),
                    );
                  }
                  // Synced: compute active line + auto-scroll.
                  var active = 0;
                  for (var i = 0; i < r.synced.length; i++) {
                    if (posSec >= r.synced[i].time) active = i;
                  }
                  if (active != _active) {
                    _active = active;
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _autoScroll(active, r.synced.length));
                  }
                  return NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollStartNotification &&
                          n.dragDetails != null) {
                        _userScrolledAt = DateTime.now();
                      }
                      return false;
                    },
                    child: ListView.builder(
                    controller: _scroll,
                    padding:
                        const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.xxxl),
                    itemCount: r.synced.length,
                    itemBuilder: (_, i) {
                      final on = i == active;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final total = ref
                              .read(playerControllerProvider)
                              .total
                              .inMilliseconds;
                          if (total > 0) {
                            ref
                                .read(playerControllerProvider.notifier)
                                .seek(r.synced[i].time * 1000 / total);
                          }
                        },
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 280),
                          style: TextStyle(
                            fontSize: 21,
                            height: 1.5,
                            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                            color: on
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: Sp.sm),
                            child: Text(r.synced[i].text),
                          ),
                        ),
                      );
                    },
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

class _Empty extends StatelessWidget {
  final TextTheme text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lyrics_outlined,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: Sp.md),
            Text('No lyrics found', style: text.titleMedium),
            const SizedBox(height: Sp.xs),
            Text('We couldn’t match this track', style: text.bodyMedium),
          ],
        ),
      );
}
