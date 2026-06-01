import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Standard gap between RSP / L&D record action controls.
const double kRspLdRecordActionGap = 8;

/// Shared icon-button chrome for view / print / PDF actions.
ButtonStyle rspLdRecordIconButtonStyle({Color? foreground}) {
  final navy = foreground ?? AppTheme.primaryNavy;
  return IconButton.styleFrom(
    foregroundColor: navy,
    backgroundColor: navy.withValues(alpha: 0.1),
    minimumSize: const Size(40, 40),
    padding: const EdgeInsets.all(8),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// Stacked or inline view + print icon buttons (saved-records browser, narrow cells).
class RspLdViewPrintIconActions extends StatelessWidget {
  const RspLdViewPrintIconActions({
    super.key,
    required this.onView,
    required this.onPrint,
    this.axis = Axis.vertical,
    this.iconSize = 22,
    this.gap = kRspLdRecordActionGap,
  });

  final VoidCallback onView;
  final VoidCallback onPrint;
  final Axis axis;
  final double iconSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final style = rspLdRecordIconButtonStyle();
    final viewBtn = IconButton(
      tooltip: 'View',
      style: style,
      onPressed: onView,
      icon: Icon(Icons.visibility_rounded, size: iconSize),
    );
    final printBtn = IconButton(
      tooltip: 'Print',
      style: style,
      onPressed: onPrint,
      icon: Icon(Icons.print_rounded, size: iconSize),
    );

    if (axis == Axis.horizontal) {
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [viewBtn, printBtn],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        viewBtn,
        SizedBox(height: gap),
        printBtn,
      ],
    );
  }
}
