import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/track.dart';
import '../../state/player_controller.dart';
import '../../widgets/track_tile.dart';

/// Full vertical list behind a carousel's "See all".
class SeeAllScreen extends ConsumerWidget {
  final String title;
  final List<Track> tracks;
  const SeeAllScreen({super.key, required this.title, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playerControllerProvider).current;
    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      appBar: AppBar(
        backgroundColor: AppColors.voidBlack,
        title: Text(title),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 180),
        physics: const BouncingScrollPhysics(),
        itemCount: tracks.length,
        itemBuilder: (_, i) => TrackTile(
          track: tracks[i],
          active: playing?.id == tracks[i].id,
          onTap: () => ref
              .read(playerControllerProvider.notifier)
              .playQueue(tracks, startAt: i),
        ),
      ),
    );
  }
}
