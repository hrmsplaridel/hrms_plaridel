import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_mobile_bottom_nav.dart';

EdgeInsets employeeMainScrollPadding(
  BuildContext context, {
  bool mobileNav = false,
}) {
  final mq = MediaQuery.of(context);
  final w = mq.size.width;
  final horizontal = w > 900 ? 24.0 : (w > 600 ? 20.0 : 18.0);
  final top = w < 600 ? 4.0 : 8.0;
  var bottom = 28.0 + (w < 600 ? mq.padding.bottom * 0.5 : 0.0);
  if (mobileNav) {
    bottom += DashboardMobileBottomNav.scrollPaddingExtra(context);
  }
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}

double employeeCardPadding(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 600 ? 16.0 : 20.0;
}

double employeeSectionCardPadding(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
}
