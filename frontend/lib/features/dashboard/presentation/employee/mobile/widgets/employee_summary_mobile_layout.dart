import 'package:flutter/widgets.dart';

class EmployeeSummaryMobileLayout extends StatelessWidget {
  const EmployeeSummaryMobileLayout({
    super.key,
    required this.clockIn,
    required this.attendance,
    required this.leaveBalance,
    required this.gap,
  });

  final Widget clockIn;
  final Widget attendance;
  final Widget leaveBalance;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        clockIn,
        SizedBox(height: gap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: attendance),
            SizedBox(width: gap),
            Expanded(child: leaveBalance),
          ],
        ),
      ],
    );
  }
}
