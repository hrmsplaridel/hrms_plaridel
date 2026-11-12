import 'package:flutter/material.dart';

/// Shared phone-first layout metrics for employee L&D screens.
class LdEmployeeLayout {
  LdEmployeeLayout._();

  static const double phoneMax = 600;
  static const double phoneNarrowMax = 380;
  static const double twoColMin = 900;

  static bool isPhone(double width) => width < phoneMax;
  static bool isPhoneNarrow(double width) => width < phoneNarrowMax;
  static bool isTwoCol(double width) => width >= twoColMin;

  /// Outer card padding — roomy on tablet, breathable on phones.
  static EdgeInsets cardPadding(double width) {
    if (isPhoneNarrow(width)) {
      return const EdgeInsets.fromLTRB(12, 12, 12, 12);
    }
    if (isPhone(width)) {
      return const EdgeInsets.fromLTRB(14, 14, 14, 14);
    }
    return const EdgeInsets.fromLTRB(20, 18, 20, 18);
  }

  static double sectionGap(double width) {
    if (isPhoneNarrow(width)) return 12;
    if (isPhone(width)) return 14;
    return 16;
  }

  static double titleSize(double width, {double phone = 18, double desk = 28}) {
    if (isPhoneNarrow(width)) return phone - 1;
    if (isPhone(width)) return phone;
    return desk;
  }

  static double bodySize(double width) {
    if (isPhoneNarrow(width)) return 13;
    if (isPhone(width)) return 13.5;
    return 14.5;
  }

  /// History / side panels: full-bleed on phones, inset drawer on larger screens.
  static ({
    double width,
    double top,
    double bottom,
    double right,
    bool fullBleed,
  })
  sidePanelMetrics(MediaQueryData mq) {
    final w = mq.size.width;
    final phone = isPhone(w);
    return (
      width: phone ? w : (w < 720 ? w - 12 : 440.0),
      top: phone ? mq.padding.top : (w < 720 ? mq.padding.top + 8 : 12.0),
      bottom: phone
          ? mq.padding.bottom
          : (w < 720 ? mq.padding.bottom + 8 : 12.0),
      right: phone ? 0.0 : (w < 720 ? 0.0 : 16.0),
      fullBleed: phone,
    );
  }
}
