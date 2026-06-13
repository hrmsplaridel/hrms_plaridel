import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/desktop/pages/employee_locator_slip_desktop_page.dart'
    as desktop;
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/pages/employee_locator_slip_mobile_page.dart';

class EmployeeLocatorSlipScreen extends StatefulWidget {
  const EmployeeLocatorSlipScreen({super.key});

  @override
  State<EmployeeLocatorSlipScreen> createState() =>
      EmployeeLocatorSlipScreenState();
}

class EmployeeLocatorSlipScreenState extends State<EmployeeLocatorSlipScreen> {
  final GlobalKey<desktop.EmployeeLocatorSlipScreenState> _desktopKey =
      GlobalKey<desktop.EmployeeLocatorSlipScreenState>();
  final GlobalKey<EmployeeLocatorSlipMobilePageState> _mobileKey =
      GlobalKey<EmployeeLocatorSlipMobilePageState>();

  Future<void> openCreateForm() async {
    if (PlatformLayout.isMobile(context)) {
      await _mobileKey.currentState?.openCreateForm();
      return;
    }
    await _desktopKey.currentState?.openCreateForm();
  }

  @override
  Widget build(BuildContext context) {
    final child = PlatformLayout.isMobile(context)
        ? EmployeeLocatorSlipMobilePage(key: _mobileKey)
        : desktop.EmployeeLocatorSlipScreen(key: _desktopKey);
    return child;
  }
}
