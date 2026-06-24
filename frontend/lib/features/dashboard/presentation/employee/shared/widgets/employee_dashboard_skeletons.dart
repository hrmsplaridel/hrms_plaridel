import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

const _kDashShimmerPeriod = Duration(milliseconds: 1200);

class _DashBone extends StatelessWidget {
  const _DashBone({
    required this.width,
    required this.height,
    this.borderRadius = 6,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Shimmer.fromColors(
      baseColor: dark
          ? const Color(0xFF2A3140)
          : AppTheme.lightGray.withValues(alpha: 0.55),
      highlightColor: dark ? const Color(0xFF3D4451) : AppTheme.white,
      period: _kDashShimmerPeriod,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xFF343B4A)
                : AppTheme.lightGray.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
    );
  }
}

/// Shimmer body for [EmployeeAttendanceOverviewCard] while month records load.
class AttendanceOverviewLoadingBody extends StatelessWidget {
  const AttendanceOverviewLoadingBody({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w < 560;

    return Semantics(
      label: 'Loading attendance overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final cw = c.maxWidth;
              final crossAxisCount = cw >= 720
                  ? 5
                  : cw >= 440
                  ? 3
                  : 2;
              const spacing = 8.0;
              final tileHeight = cw >= 440 ? 72.0 : 68.0;
              final tileWidth =
                  (cw - (spacing * (crossAxisCount - 1))) / crossAxisCount;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: tileWidth / tileHeight,
                children: List.generate(5, (_) => const _KpiTileSkeleton()),
              );
            },
          ),
          SizedBox(height: narrow ? 10 : 12),
          _DistributionPanelSkeleton(narrow: narrow),
        ],
      ),
    );
  }
}

class _KpiTileSkeleton extends StatelessWidget {
  const _KpiTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Row(
              children: [
                _DashBone(width: 16, height: 16, borderRadius: 4),
                Spacer(),
                _DashBone(width: 30, height: 20, borderRadius: 5),
              ],
            ),
            const SizedBox(height: 5),
            const _DashBone(width: 72, height: 11, borderRadius: 4),
          ],
        ),
      ),
    );
  }
}

class _DistributionPanelSkeleton extends StatelessWidget {
  const _DistributionPanelSkeleton({required this.narrow});

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(narrow ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.offWhite.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _DashBone(width: 96, height: 14, borderRadius: 4),
              const Spacer(),
              const _DashBone(width: 72, height: 11, borderRadius: 4),
            ],
          ),
          SizedBox(height: narrow ? 8 : 10),
          SizedBox(
            height: narrow ? 48 : 54,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final h in [0.45, 0.72, 0.35, 0.58, 0.88])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _DashBone(
                        width: double.infinity,
                        height: (narrow ? 82 : 92) * h,
                        borderRadius: 6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer placeholder for the dashboard “Leave Balance” summary card.
class LeaveBalanceSummaryCardSkeleton extends StatelessWidget {
  const LeaveBalanceSummaryCardSkeleton({super.key, required this.padding});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading leave balance',
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _DashBone(width: 96, height: 13, borderRadius: 4),
                  const SizedBox(height: 12),
                  const _DashBone(width: 88, height: 28, borderRadius: 8),
                  const SizedBox(height: 8),
                  const _DashBone(width: 112, height: 12, borderRadius: 4),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _DashBone(width: 64, height: 11, borderRadius: 4),
                              SizedBox(height: 4),
                              _DashBone(width: 40, height: 14, borderRadius: 4),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _DashBone(width: 48, height: 11, borderRadius: 4),
                              SizedBox(height: 4),
                              _DashBone(width: 40, height: 14, borderRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _DashBone(width: 48, height: 48, borderRadius: 14),
          ],
        ),
      ),
    );
  }
}

/// Shimmer table placeholder for My Attendance while records load.
class EmployeeTimeRecordsLoadingSkeleton extends StatelessWidget {
  const EmployeeTimeRecordsLoadingSkeleton({super.key});

  static const _minTableWidth = 860.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading time records',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < _minTableWidth
              ? _minTableWidth
              : constraints.maxWidth;
          return Container(
            decoration: AppTheme.dashSurfaceCard(context, radius: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.dashMutedSurfaceOf(context),
                          border: Border(
                            bottom: BorderSide(
                              color: AppTheme.dashHairlineOf(context),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            for (final flex in [2, 1, 1, 1, 1, 1, 1, 2])
                              Expanded(
                                flex: flex,
                                child: Center(
                                  child: _DashBone(
                                    width: flex == 2 ? 56 : 44,
                                    height: 12,
                                    borderRadius: 4,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < 7; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: i.isEven
                                ? AppTheme.dashPanelOf(context)
                                : AppTheme.dashMutedSurfaceOf(context),
                            border: Border(
                              top: BorderSide(
                                color: AppTheme.dashHairlineOf(context),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              for (final flex in [2, 1, 1, 1, 1, 1, 1, 2])
                                Expanded(
                                  flex: flex,
                                  child: Center(
                                    child: _DashBone(
                                      width: flex == 2
                                          ? (i.isEven ? 72 : 64)
                                          : 36,
                                      height: 11,
                                      borderRadius: 4,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
