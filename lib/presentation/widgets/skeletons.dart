import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Single shimmering placeholder block.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius radius;
  const SkeletonBox(
      {super.key,
      required this.width,
      required this.height,
      this.radius = Radii.rMd});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.elevated,
      highlightColor: AppColors.elevatedHi,
      period: const Duration(milliseconds: 1400),
      child: Container(
        width: width,
        height: height,
        decoration:
            BoxDecoration(color: AppColors.elevated, borderRadius: radius),
      ),
    );
  }
}

/// Horizontal carousel skeleton matching the real card layout.
class CarouselSkeleton extends StatelessWidget {
  final double cardSize;
  const CarouselSkeleton({super.key, this.cardSize = 150});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: cardSize + 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: Sp.md),
        itemBuilder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: cardSize, height: cardSize, radius: Radii.rLg),
            const SizedBox(height: Sp.sm),
            SkeletonBox(width: cardSize * 0.8, height: 12),
            const SizedBox(height: Sp.xs),
            SkeletonBox(width: cardSize * 0.5, height: 10),
          ],
        ),
      ),
    );
  }
}
