import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'glass.dart';

class NavDest {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const NavDest(this.icon, this.activeIcon, this.label);
}

/// Floating glass bottom bar. Active item gets an emerald pill + glow.
class FrostedNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<NavDest> destinations;

  const FrostedNavBar({
    super.key,
    required this.index,
    required this.onTap,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
      child: Glass(
        radius: Radii.rPill,
        blur: 24,
        opacity: 0.10,
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < destinations.length; i++)
              _NavItem(
                dest: destinations[i],
                selected: i == index,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavDest dest;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(
      {required this.dest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: Sp.xs),
          padding: const EdgeInsets.symmetric(vertical: Sp.md),
          decoration: BoxDecoration(
            borderRadius: Radii.rPill,
            color: selected ? AppColors.accentSoft : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? dest.activeIcon : dest.icon,
                size: 24,
                color: selected
                    ? AppColors.accentBright
                    : AppColors.textSecondary,
                shadows: selected
                    ? [
                        const Shadow(
                            color: AppColors.accentBright, blurRadius: 14),
                      ]
                    : null,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: Sp.sm),
                        child: Text(
                          dest.label,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: AppColors.accentBright),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
