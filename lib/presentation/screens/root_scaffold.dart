import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../state/player_controller.dart';
import '../widgets/ambient_background.dart';
import '../widgets/frosted_nav_bar.dart';
import '../widgets/mini_player.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'search/search_screen.dart';

/// Top-level shell: ambient bg + page body + persistent mini-player + glass nav.
class RootScaffold extends ConsumerStatefulWidget {
  const RootScaffold({super.key});
  @override
  ConsumerState<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends ConsumerState<RootScaffold> {
  int _index = 0;

  static const _destinations = [
    NavDest(Icons.home_outlined, Icons.home_rounded, 'Home'),
    NavDest(Icons.search_outlined, Icons.search_rounded, 'Search'),
    NavDest(Icons.library_music_outlined, Icons.library_music_rounded,
        'Library'),
  ];

  static const _pages = [HomeScreen(), SearchScreen(), LibraryScreen()];

  @override
  Widget build(BuildContext context) {
    // Ambient color follows the current track for a cohesive vibe.
    final seed = ref.watch(playerControllerProvider).current?.accent ??
        AppColors.accent;

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        seed: seed,
        child: Stack(
          children: [
            // Animated cross-fade between tabs.
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOut,
                child: KeyedSubtree(
                  key: ValueKey(_index),
                  child: _pages[_index],
                ),
              ),
            ),
            // Mini-player + nav bar pinned to the bottom.
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiniPlayer(),
                  SafeArea(
                    top: false,
                    child: FrostedNavBar(
                      index: _index,
                      destinations: _destinations,
                      onTap: (i) => setState(() => _index = i),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
