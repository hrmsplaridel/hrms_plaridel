import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/desktop/pages/dtr_dashboard_desktop_page.dart'
    as desktop;
import 'package:hrms_plaridel/features/dtr/attendance/presentation/mobile/pages/dtr_dashboard_mobile_page.dart';

class DtrDashboard extends StatelessWidget {
  const DtrDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    if (PlatformLayout.isMobile(context)) {
      return const DtrDashboardMobilePage();
    }
    return const desktop.DtrDashboard();
  }
}
