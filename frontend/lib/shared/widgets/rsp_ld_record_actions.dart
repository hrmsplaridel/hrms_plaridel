import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/form_document_preview.dart';

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
    this.onDocumentPreview,
    this.axis = Axis.vertical,
    this.iconSize = 22,
    this.gap = kRspLdRecordActionGap,
  });

  final VoidCallback onView;
  final FutureOr<void> Function() onPrint;
  final FutureOr<void> Function()? onDocumentPreview;
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
    final previewBtn = onDocumentPreview == null
        ? null
        : RspLdBusyIconButton(
            tooltip: 'Preview Form',
            icon: Icons.visibility_outlined,
            iconSize: iconSize,
            busyTooltip: 'Opening preview…',
            onPressed: onDocumentPreview!,
          );
    final printBtn = RspLdBusyIconButton(
      tooltip: 'Print Form',
      icon: Icons.print_rounded,
      iconSize: iconSize,
      busyTooltip: 'Preparing print…',
      onPressed: onPrint,
    );
    final buttons = [
      viewBtn,
      if (previewBtn != null) previewBtn,
      printBtn,
    ];

    if (axis == Axis.horizontal) {
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: buttons,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          buttons[i],
        ],
      ],
    );
  }
}
