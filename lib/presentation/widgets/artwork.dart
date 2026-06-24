import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/track.dart';

/// Rounded album art with graceful gradient fallback (works offline too).
class Artwork extends StatelessWidget {
  final Track track;
  final double size;
  final BorderRadius radius;
  final bool glow;

  const Artwork({
    super.key,
    required this.track,
    this.size = 56,
    this.radius = const BorderRadius.all(Radius.circular(12)),
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: track.accent.withValues(alpha: 0.45),
                  blurRadius: 48,
                  spreadRadius: -8,
                  offset: const Offset(0, 16),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: _image(),
      ),
    );
  }

  Widget _image() {
    // Local/device tracks: soft gradient fallback (no plugin — it crashed).
    if (track.artworkUrl.isEmpty) return _fallback();
    return CachedNetworkImage(
      imageUrl: track.artworkUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 350),
      placeholder: (_, __) => _fallback(),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [track.accent.withValues(alpha: 0.8), AppColors.elevated],
          ),
        ),
        child: Center(
          child: Icon(Icons.music_note_rounded,
              color: Colors.white.withValues(alpha: 0.7), size: size * 0.35),
        ),
      );
}
