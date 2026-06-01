import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

const _kShimmerPeriod = Duration(milliseconds: 1200);

/// Shimmer placeholder for [EmployeeLeaveScreen] initial load (empty data + loading).
class MyLeaveLoadingSkeleton extends StatelessWidget {
  const MyLeaveLoadingSkeleton({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading leave information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            Column(
              children: [
                const _SummarySkeletonCard(),
                const SizedBox(height: 16),
                const _SummarySkeletonCard(),
                const SizedBox(height: 16),
                const _SummarySkeletonCard(),
              ],
            )
          else
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SummarySkeletonCard()),
                SizedBox(width: 16),
                Expanded(child: _SummarySkeletonCard()),
                SizedBox(width: 16),
                Expanded(child: _SummarySkeletonCard()),
              ],
            ),
          const SizedBox(height: 24),
          _SectionSkeleton(
            title: 'Leave Balances',
            subtitle: 'Available and pending credits per leave type.',
            icon: Icons.account_balance_wallet_rounded,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final n = constraints.maxWidth < 600
                    ? 1
                    : (constraints.maxWidth < 960 ? 2 : 3);
                final w = (constraints.maxWidth - (n - 1) * 12) / n;
                final count = n == 1 ? 2 : (n == 2 ? 4 : 6);
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(
                    count,
                    (_) => SizedBox(
                      width: n == 1 ? constraints.maxWidth : w,
                      child: const _BalanceCardSkeleton(),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _SectionSkeleton(
            title: 'My Requests',
            subtitle: 'Recent leave applications and their current status.',
            icon: Icons.event_note_rounded,
            child: Column(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: _RequestCardSkeleton(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({
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
          ? AppTheme.dashMutedSurfaceOf(context)
          : AppTheme.lightGray.withValues(alpha: 0.55),
      highlightColor: dark ? AppTheme.dashHairlineOf(context) : AppTheme.white,
      period: _kShimmerPeriod,
      child: SizedBox(
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
      ),
    );
  }
}

class _SummarySkeletonCard extends StatelessWidget {
  const _SummarySkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Bone(width: 22, height: 22, borderRadius: 6),
          const SizedBox(height: 14),
          const _Bone(width: 140, height: 12, borderRadius: 4),
          const SizedBox(height: 10),
          const _Bone(width: 72, height: 24, borderRadius: 8),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) =>
                _Bone(width: c.maxWidth * 0.92, height: 12, borderRadius: 4),
          ),
        ],
      ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.primaryNavy, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _BalanceCardSkeleton extends StatelessWidget {
  const _BalanceCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Bone(width: 120, height: 14, borderRadius: 4),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _Bone(width: 72, height: 36, borderRadius: 8),
              _Bone(width: 64, height: 36, borderRadius: 8),
              _Bone(width: 76, height: 36, borderRadius: 8),
              _Bone(width: 88, height: 36, borderRadius: 8),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestCardSkeleton extends StatelessWidget {
  const _RequestCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Bone(width: 160, height: 16, borderRadius: 4),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, c) => _Bone(
                        width: c.maxWidth * 0.75,
                        height: 12,
                        borderRadius: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const _Bone(width: 88, height: 28, borderRadius: 14),
            ],
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Bone(width: 96, height: 32, borderRadius: 8),
              _Bone(width: 120, height: 32, borderRadius: 8),
            ],
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Bone(width: 100, height: 36, borderRadius: 8),
              _Bone(width: 108, height: 36, borderRadius: 8),
              _Bone(width: 88, height: 36, borderRadius: 8),
            ],
          ),
        ],
      ),
    );
  }
}
