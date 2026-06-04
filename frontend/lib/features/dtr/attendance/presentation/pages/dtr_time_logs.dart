import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/desktop/pages/dtr_time_logs_desktop_page.dart'
    as desktop;
import 'package:hrms_plaridel/features/dtr/attendance/presentation/mobile/pages/dtr_time_logs_mobile_page.dart';

class DtrTimeLogs extends StatelessWidget {
  const DtrTimeLogs({super.key});

  @override
  Widget build(BuildContext context) {
    if (PlatformLayout.isMobile(context)) {
      return const DtrTimeLogsMobilePage();
    }
    return const desktop.DtrTimeLogs();
  }
}
