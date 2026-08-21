import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../state/providers.dart';
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
  @override
  void initState() {
    super.initState();
    // Tapping a download notification jumps to Library → Queue.
    NotificationService.instance.onOpenDownloads = () {
      if (!mounted) return;
      ref.read(navIndexProvider.notifier).state = 2;
      ref.read(libraryTabProvider.notifier).state = 3;
    };
  }

  static const _destinations = [
    NavDest(Icons.home_outlined, Icons.home_rounded, 'Home'),
    NavDest(Icons.search_outlined, Icons.search_rounded, 'Search'),
    NavDest(Icons.library_music_outlined, Icons.library_music_rounded,
        'Library'),
  ];

  static const _pages = [HomeScreen(), SearchScreen(), LibraryScreen()];

  DateTime? _lastBackPressTime;

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (index != 0) {
          ref.read(navIndexProvider.notifier).state = 0;
          return;
        }

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Press back again to exit',
                style: TextStyle(color: Colors.white),
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.elevated,
            ),
          );
          return;
        }

        SystemNavigator.pop();
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: AmbientBackground(
          // Constant, subtle brand tint on browse screens — track-colored blobs
          // bleeding under the header looked messy. The player has its own veil.
          seed: AppColors.accent,
          child: Stack(
            children: [
              // Keep all tabs alive (no rebuild/refetch) for instant, smooth
              // switching — IndexedStack instead of a rebuilding switcher.
              Positioned.fill(
                child: IndexedStack(index: index, children: _pages),
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
                        index: index,
                        destinations: _destinations,
                        onTap: (i) =>
                            ref.read(navIndexProvider.notifier).state = i,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
