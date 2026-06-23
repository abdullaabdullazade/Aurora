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

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _filter = 0;
  static const _filters = ['Tracks', 'Videos', 'Playlists', 'Albums'];

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                style: text.bodyLarge,
                cursorColor: AppColors.accentBright,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Songs, artists, videos…',
                  hintStyle: text.bodyLarge
                      ?.copyWith(color: AppColors.textTertiary),
                  icon: const Icon(Icons.search_rounded,
                      color: AppColors.textSecondary),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _ctrl.clear();
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
            child: query.isEmpty
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
                              trailing: const Icon(
                                  Icons.arrow_circle_down_rounded,
                                  color: AppColors.textSecondary),
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
