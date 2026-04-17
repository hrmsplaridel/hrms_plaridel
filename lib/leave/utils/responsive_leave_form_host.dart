import 'package:flutter/material.dart';

import '../../utils/responsive_right_side_panel.dart';

/// Opens a leave form as:
/// - full screen route on small screens
/// - right-side slide-in panel on wide screens (resizable drag handle on the left edge)
Future<T?> openResponsiveLeaveFormHost<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double breakpoint = 1100,
}) {
  return openResponsiveRightSidePanel<T>(
    context: context,
    builder: builder,
    breakpoint: breakpoint,
    barrierLabel: 'Close leave form',
    minWidth: 760,
    initialWidthFraction: 0.52,
  );
}
