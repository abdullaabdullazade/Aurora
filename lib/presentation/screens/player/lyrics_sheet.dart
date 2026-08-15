import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../widgets/glass.dart';
import '../../state/lyrics_controller.dart';
import '../../state/player_controller.dart';
import 'lyric_card_sheet.dart';

/// Real synced lyrics (lrclib via resolver). Highlights + auto-scrolls the
/// active line; tap a line to seek to it. Falls back to plain text, then to a
/// graceful empty state.
class LyricsSheet extends ConsumerStatefulWidget {
  const LyricsSheet({super.key});
  @override
  ConsumerState<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends ConsumerState<LyricsSheet> {
  // Index-based controller → exact jump to the active line regardless of how
  // many visual rows each (possibly wrapped) lyric occupies.
  final _itemScroll = ItemScrollController();
  int _active = -1;
  DateTime? _userScrolledAt; // suspend auto-scroll after a manual scroll
  bool _firstScroll = true; // first jump (on open) is instant

  // Active line sits ~38% from the top — reads naturally, with upcoming lines
  // visible below.
  static const double _align = 0.38;

  void _autoScroll(int index) {
    if (!_itemScroll.isAttached || index < 0) return;
    // Don't yank the view while the user is reading/scrolling manually.
    final last = _userScrolledAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 6)) {
      return;
    }
    if (_firstScroll) {
      _firstScroll = false;
      _itemScroll.jumpTo(index: index, alignment: _align); // open at current line
    } else {
      _itemScroll.scrollTo(
        index: index,
        alignment: _align,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(lyricsProvider);
    // Watch whole seconds only — rebuilding 4×/sec made the sheet janky.
    final posSec = ref
        .watch(playerControllerProvider.select((s) => s.position.inSeconds))
        .toDouble();
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, sheetScroll) => Glass(
        radius: const BorderRadius.vertical(top: Radii.xl),
        blur: 18,
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
                const SizedBox(width: Sp.sm),
                Text('· hold a line to share',
                    style: text.labelSmall
                        ?.copyWith(color: AppColors.textTertiary)),
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
                        (_) => _autoScroll(active));
                  }
                  return NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollStartNotification &&
                          n.dragDetails != null) {
                        _userScrolledAt = DateTime.now();
                      }
                      return false;
                    },
                    child: ScrollablePositionedList.builder(
                    itemScrollController: _itemScroll,
                    initialScrollIndex: active, // open already at the current line
                    initialAlignment: _align,
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
                        // Long-press turns this line (and the ones after it)
                        // into a shareable card.
                        onLongPress: () {
                          final track =
                              ref.read(playerControllerProvider).current;
                          if (track == null) return;
                          HapticFeedback.mediumImpact();
                          LyricCardSheet.show(
                            context,
                            track: track,
                            lines: [
                              for (final l in r.synced) l.text,
                            ],
                            startIndex: i,
                          );
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
