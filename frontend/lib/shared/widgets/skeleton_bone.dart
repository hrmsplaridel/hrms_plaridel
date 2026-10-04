import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Shared placeholder styling used by leave and settings loading states.
class SkeletonBone extends StatelessWidget {
  const SkeletonBone({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 6,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final shape = SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark
              ? AppTheme.dashHairlineOf(context)
              : AppTheme.lightGray.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return shape;
    return Shimmer.fromColors(
      baseColor: dark
          ? AppTheme.dashMutedSurfaceOf(context)
          : AppTheme.lightGray.withValues(alpha: 0.55),
      highlightColor: dark ? AppTheme.dashHairlineOf(context) : AppTheme.white,
      period: const Duration(milliseconds: 1200),
      child: shape,
    );
  }
}
