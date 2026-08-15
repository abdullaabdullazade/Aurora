import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/dynamic_palette.dart';
import '../../../domain/entities/track.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass.dart';

/// Turns a few lyric lines into a shareable image.
///
/// The card is a real widget captured with [RepaintBoundary], not a
/// screenshot of the sheet — so it renders at a fixed 3x and keeps the
/// artwork's own colors regardless of what the phone was showing.
class LyricCardSheet extends StatefulWidget {
  final Track track;

  /// Every line of the song, and where the selection starts. The user grows or
  /// shrinks the selection from there.
  final List<String> lines;
  final int startIndex;

  const LyricCardSheet({
    super.key,
    required this.track,
    required this.lines,
    required this.startIndex,
  });

  static Future<void> show(
    BuildContext context, {
    required Track track,
    required List<String> lines,
    required int startIndex,
  }) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => LyricCardSheet(
            track: track, lines: lines, startIndex: startIndex),
      );

  @override
  State<LyricCardSheet> createState() => _LyricCardSheetState();
}

class _LyricCardSheetState extends State<LyricCardSheet> {
  final _boundary = GlobalKey();
  late int _count = _initialCount;
  bool _busy = false;

  static const _maxLines = 6;

  int get _initialCount =>
      (widget.lines.length - widget.startIndex).clamp(1, 4);

  int get _maxAvailable =>
      (widget.lines.length - widget.startIndex).clamp(1, _maxLines);

  List<String> get _selected => widget.lines
      .skip(widget.startIndex)
      .take(_count)
      .where((l) => l.trim().isNotEmpty)
      .toList();

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary = _boundary.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('empty image');

      final dir = await getTemporaryDirectory();
      final safe = widget.track.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/aurora_$safe.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '${widget.track.title} — ${widget.track.artist}',
      );
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.elevated,
        content: Text('Could not build the card'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Glass(
      radius: const BorderRadius.vertical(top: Radii.xl),
      blur: 30,
      opacity: 0.16,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Sp.md),
            Container(
                width: 44,
                height: 4,
                decoration: const BoxDecoration(
                    color: AppColors.glassStroke,
                    borderRadius: Radii.rPill)),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Row(
                children: [
                  Text('Share lyrics', style: text.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Fewer lines',
                    onPressed: _count > 1
                        ? () => setState(() => _count--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text('$_count', style: text.titleMedium),
                  IconButton(
                    tooltip: 'More lines',
                    onPressed: _count < _maxAvailable
                        ? () => setState(() => _count++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: RepaintBoundary(
                key: _boundary,
                child: _Card(track: widget.track, lines: _selected),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: Sp.md),
                  ),
                  onPressed: _busy ? null : _share,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.ios_share_rounded),
                  label: Text(_busy ? 'Rendering…' : 'Share image'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The image itself. Fixed aspect so the export is predictable.
class _Card extends StatelessWidget {
  final Track track;
  final List<String> lines;
  const _Card({required this.track, required this.lines});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        borderRadius: Radii.rLg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Tone.backdropHi(track.accent),
            Tone.backdrop(track.accent),
            AppColors.voidBlack,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                l,
                style: text.titleLarge?.copyWith(
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          const SizedBox(height: Sp.lg),
          Row(
            children: [
              ClipRRect(
                borderRadius: Radii.rSm,
                child: Artwork(track: track, size: 44),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall
                            ?.copyWith(color: AppColors.textPrimary)),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: Sp.md),
              Text('Aurora',
                  style: text.labelSmall?.copyWith(
                      color: Tone.accent(track.accent),
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}
