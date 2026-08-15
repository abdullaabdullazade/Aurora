import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../state/player_controller.dart';
import '../../state/providers.dart';
import '../../widgets/glass.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/track_tile.dart';
import '../library/add_to_playlist_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _filter = 0;
  static const _filters = ['Tracks', 'Playlists', 'Albums'];

  /// Raw field text. The provider holds the *debounced* query, so this is what
  /// autocomplete has to follow — otherwise suggestions lag a keystroke behind.
  String _typed = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  void _onChanged(String value) {
    setState(() => _typed = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  /// Runs [q] now: no debounce, remembered in history, keyboard dismissed.
  Future<void> _commit(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _ctrl.text = query;
    _ctrl.selection = TextSelection.collapsed(offset: query.length);
    setState(() => _typed = query);
    ref.read(searchQueryProvider.notifier).state = query;
    _focus.unfocus();
    await ref.read(localStoreProvider).pushSearch(query);
    ref.invalidate(searchHistoryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final text = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Search', style: text.displayLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: Glass(
              radius: Radii.rPill,
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: _onChanged,
                onSubmitted: _commit,
                textInputAction: TextInputAction.search,
                style: text.bodyLarge,
                cursorColor: AppColors.accentBright,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: 'Songs, artists, videos…',
                  hintStyle: text.bodyLarge
                      ?.copyWith(color: AppColors.textTertiary),
                  icon: const Icon(Icons.search_rounded,
                      color: AppColors.textSecondary),
                  suffixIcon: _typed.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _typed = '');
                            ref.read(searchQueryProvider.notifier).state = '';
                          },
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: Sp.sm),
              itemBuilder: (_, i) => _FilterChip(
                label: _filters[i],
                selected: i == _filter,
                onTap: () => setState(() => _filter = i),
              ),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Expanded(
            child: _focus.hasFocus
                // While the field is focused the useful thing to show is where
                // to go next, not stale results for a half-typed word.
                ? _Assist(
                    typed: _typed,
                    onPick: _commit,
                  )
                : query.isEmpty
                ? _Empty(text: text)
                : results.when(
                    loading: () => ListView.builder(
                      padding: const EdgeInsets.all(Sp.lg),
                      itemCount: 8,
                      itemBuilder: (_, __) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: Sp.sm),
                        child: Row(children: [
                          SkeletonBox(width: 52, height: 52),
                          SizedBox(width: Sp.md),
                          Expanded(child: SkeletonBox(width: 0, height: 16)),
                        ]),
                      ),
                    ),
                    error: (_, __) =>
                        Center(child: Text('Search failed', style: text.bodyMedium)),
                    data: (tracks) => tracks.isEmpty
                        ? Center(
                            child: Text('No results for “$query”',
                                style: text.bodyMedium))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                Sp.sm, 0, Sp.sm, 180),
                            itemCount: tracks.length,
                            itemBuilder: (_, i) => TrackTile(
                              track: tracks[i],
                              onTap: () => ref
                                  .read(playerControllerProvider.notifier)
                                  .playQueue(tracks, startAt: i),
                              trailing: IconButton(
                                icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                    color: AppColors.textSecondary),
                                onPressed: () => AddToPlaylistSheet.show(
                                    context, tracks[i]),
                              ),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: Radii.rPill,
          gradient: selected ? AppColors.accentSweep : null,
          color: selected ? null : AppColors.glassFill,
          border: Border.all(
              color:
                  selected ? Colors.transparent : AppColors.glassStroke),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? Colors.black : AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Focused-field panel: past queries when the box is empty, live autocomplete
/// once there is something to complete.
class _Assist extends ConsumerWidget {
  final String typed;
  final ValueChanged<String> onPick;
  const _Assist({required this.typed, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final q = typed.trim();

    if (q.length < 2) {
      final history = ref.watch(searchHistoryProvider);
      if (history.isEmpty) return _Empty(text: text);
      return ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 180),
        children: [
          Row(
            children: [
              Text('Recent searches', style: text.labelLarge),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  await ref.read(localStoreProvider).clearSearchHistory();
                  ref.invalidate(searchHistoryProvider);
                },
                child: Text('Clear',
                    style: text.labelSmall
                        ?.copyWith(color: AppColors.accentBright)),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          for (final h in history)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.history_rounded,
                  color: AppColors.textSecondary),
              title: Text(h, style: text.bodyLarge),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textTertiary),
                onPressed: () async {
                  await ref.read(localStoreProvider).removeSearch(h);
                  ref.invalidate(searchHistoryProvider);
                },
              ),
              onTap: () => onPick(h),
            ),
        ],
      );
    }

    final suggestions = ref.watch(searchSuggestionsProvider(q));
    return suggestions.when(
      // No spinner and no error state: autocomplete that flickers or shouts is
      // worse than autocomplete that is quietly absent.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 180),
        itemCount: list.length,
        itemBuilder: (_, i) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.search_rounded,
              color: AppColors.textSecondary),
          title: Text(list[i], style: text.bodyLarge),
          trailing: const Icon(Icons.north_west_rounded,
              size: 16, color: AppColors.textTertiary),
          onTap: () => onPick(list[i]),
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
            const Icon(Icons.graphic_eq_rounded,
                size: 64, color: AppColors.textTertiary),
            const SizedBox(height: Sp.md),
            Text('Find your next favorite', style: text.titleMedium),
            const SizedBox(height: Sp.xs),
            Text('Search millions of tracks & videos',
                style: text.bodyMedium),
          ],
        ),
      );
}
