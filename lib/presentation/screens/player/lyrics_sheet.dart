import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  String _offsetLabel(int millis) {
    final seconds = millis / 1000;
    return '${seconds >= 0 ? '+' : ''}${seconds.toStringAsFixed(1)}s';
  }

  void _showOffsetEditor(String trackId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.elevated,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final offset = ref.watch(lyricsOffsetProvider(trackId));
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Lyrics timing',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: Sp.xs),
                  Text(
                    'Positive delay shows each line later.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Sp.lg),
                  Text(_offsetLabel(offset),
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: Sp.md),
                  Wrap(
                    spacing: Sp.sm,
                    children: [
                      for (final delta in [-5000, -1000, 1000, 5000])
                        OutlinedButton(
                          onPressed: () =>
                              setLyricsOffset(ref, trackId, offset + delta),
                          child: Text(
                            '${delta > 0 ? '+' : ''}${delta ~/ 1000}s',
                          ),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: offset == 0
                        ? null
                        : () => setLyricsOffset(ref, trackId, 0),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

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
      _itemScroll.jumpTo(
          index: index, alignment: _align); // open at current line
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
    final trackId = ref
        .watch(playerControllerProvider.select((state) => state.current?.id));
    final offsetMillis =
        trackId == null ? 0 : ref.watch(lyricsOffsetProvider(trackId));
    final offsetSeconds = offsetMillis / 1000;
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
                          if (offsetMillis != 0) ...[
                            const SizedBox(width: Sp.xs),
                            Text(_offsetLabel(offsetMillis),
                                style: text.labelSmall
                                    ?.copyWith(color: AppColors.accentBright)),
                          ],
                          if (trackId != null)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Adjust lyrics timing',
                              onPressed: () => _showOffsetEditor(trackId),
                              icon: const Icon(Icons.tune_rounded, size: 18),
                            ),
                        ])
                      : const SizedBox.shrink(),
                  orElse: () => const SizedBox.shrink(),
                ),
              ]),
            ),
            lyrics.maybeWhen(
              data: (result) => result.timingIssue == null ||
                      (result.timingIssue == 'possible_video_intro' &&
                          offsetMillis != 0)
                  ? const SizedBox.shrink()
                  : _TimingWarning(
                      issue: result.timingIssue!,
                      suggestedOffset: result.suggestedOffset,
                      onApply: trackId == null || result.suggestedOffset == null
                          ? null
                          : () => setLyricsOffset(
                                ref,
                                trackId,
                                (result.suggestedOffset! * 1000).round(),
                              ),
                    ),
              orElse: () => const SizedBox.shrink(),
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
                      padding:
                          const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.xxxl),
                      child: Text(r.plain,
                          style: text.titleMedium?.copyWith(
                              height: 1.8, color: AppColors.textSecondary)),
                    );
                  }
                  // Keep every line inactive during an intro/dialogue before
                  // the first LRC timestamp. Previously index 0 was forced on
                  // from 00:00, making lyrics appear to start too early.
                  final active = r.activeIndexAt(
                    posSec,
                    offsetSeconds: offsetSeconds,
                  );
                  if (active != _active) {
                    _active = active;
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _autoScroll(active));
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
                      initialScrollIndex: active < 0 ? 0 : active,
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
                              final target = r.synced[i].time + offsetSeconds;
                              ref.read(playerControllerProvider.notifier).seek(
                                  (target * 1000 / total).clamp(0.0, 1.0));
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
                              fontWeight:
                                  on ? FontWeight.w800 : FontWeight.w600,
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

class _TimingWarning extends StatelessWidget {
  final String issue;
  final double? suggestedOffset;
  final VoidCallback? onApply;

  const _TimingWarning({
    required this.issue,
    required this.suggestedOffset,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final isIntro = issue == 'possible_video_intro';
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.accentBright.withValues(alpha: 0.10),
        borderRadius: Radii.rMd,
        border:
            Border.all(color: AppColors.accentBright.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_problem_rounded,
              size: 18, color: AppColors.accentBright),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              isIntro
                  ? 'This video may have an extra intro.'
                  : 'This video edit does not fit the synced timestamps. Showing plain lyrics.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          if (isIntro && suggestedOffset != null && onApply != null)
            TextButton(
              onPressed: onApply,
              child: Text('Try +${suggestedOffset!.toStringAsFixed(1)}s'),
            ),
        ],
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
