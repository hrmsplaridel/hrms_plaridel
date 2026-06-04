import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class EmployeeLeaveMobileLayout extends StatelessWidget {
  const EmployeeLeaveMobileLayout({
    super.key,
    this.errorBanner,
    required this.showLoading,
    required this.loadingSkeleton,
    required this.summaryStrip,
    required this.balancesPanel,
    required this.requestsPanel,
  });

  final Widget? errorBanner;
  final bool showLoading;
  final Widget loadingSkeleton;
  final Widget summaryStrip;
  final Widget balancesPanel;
  final Widget requestsPanel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Leave',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        if (errorBanner != null) ...[errorBanner!, const SizedBox(height: 16)],
        if (showLoading)
          loadingSkeleton
        else ...[
          summaryStrip,
          const SizedBox(height: 22),
          balancesPanel,
          const SizedBox(height: 16),
          requestsPanel,
        ],
      ],
    );
  }
}
