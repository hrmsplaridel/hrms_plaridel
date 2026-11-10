import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_days_card.dart';

const leaveUsagePreviewLimit = 4;

Future<void> showLeaveUsageDetails({
  required BuildContext context,
  required List<LeaveBalance> balances,
}) async {
  final usage = balances.where((balance) => balance.isUsageSummary).toList();
  await openResponsiveRightSidePanel<void>(
    context: context,
    barrierLabel: 'Close leave usage details',
    useRootNavigator: MediaQuery.sizeOf(context).width < 900,
    minWidth: 420,
    initialWidthFraction: .42,
    builder: (_) => _LeaveUsageDetailsPanel(balances: usage),
  );
}

class _LeaveUsageDetailsPanel extends StatelessWidget {
  const _LeaveUsageDetailsPanel({required this.balances});

  final List<LeaveBalance> balances;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('leave-usage-details-panel'),
      color: AppTheme.dashCanvasOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: AppTheme.dashPanelOf(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Leave Usage & Limits',
                            style: TextStyle(
                              color: AppTheme.dashTextPrimaryOf(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${balances.length} leave types',
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close leave usage details',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: balances.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) =>
                    LeaveDaysCard(balance: balances[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
