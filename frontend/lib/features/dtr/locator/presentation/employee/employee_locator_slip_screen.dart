import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_slip_form_initial_values.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/desktop/pages/employee_locator_slip_desktop_page.dart'
    as desktop;
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/pages/employee_locator_slip_mobile_page.dart';

class EmployeeLocatorSlipScreen extends StatefulWidget {
  const EmployeeLocatorSlipScreen({
    super.key,
    this.tutorialHeaderKey,
    this.tutorialRequestsKey,
    this.tutorialTabsKey,
    this.tutorialApprovalFiltersKey,
  });

  final GlobalKey? tutorialHeaderKey;
  final GlobalKey? tutorialRequestsKey;
  final GlobalKey? tutorialTabsKey;
  final GlobalKey? tutorialApprovalFiltersKey;

  @override
  State<EmployeeLocatorSlipScreen> createState() =>
      EmployeeLocatorSlipScreenState();
}

class EmployeeLocatorSlipScreenState extends State<EmployeeLocatorSlipScreen> {
  final GlobalKey<desktop.EmployeeLocatorSlipScreenState> _desktopKey =
      GlobalKey<desktop.EmployeeLocatorSlipScreenState>();
  final GlobalKey<EmployeeLocatorSlipMobilePageState> _mobileKey =
      GlobalKey<EmployeeLocatorSlipMobilePageState>();

  void showSection({required bool approvals}) {
    if (PlatformLayout.isMobile(context)) {
      _mobileKey.currentState?.showSection(approvals: approvals);
    } else {
      _desktopKey.currentState?.showSection(approvals: approvals);
    }
  }

  Future<void> openCreateForm({
    LocatorSlipFormInitialValues? initialValues,
  }) async {
    if (PlatformLayout.isMobile(context)) {
      await _mobileKey.currentState?.openCreateForm(
        initialValues: initialValues,
      );
      return;
    }
    await _desktopKey.currentState?.openCreateForm(
      initialValues: initialValues,
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = PlatformLayout.isMobile(context)
        ? EmployeeLocatorSlipMobilePage(
            key: _mobileKey,
            tutorialHeaderKey: widget.tutorialHeaderKey,
            tutorialRequestsKey: widget.tutorialRequestsKey,
            tutorialTabsKey: widget.tutorialTabsKey,
            tutorialApprovalFiltersKey: widget.tutorialApprovalFiltersKey,
          )
        : desktop.EmployeeLocatorSlipScreen(
            key: _desktopKey,
            tutorialHeaderKey: widget.tutorialHeaderKey,
            tutorialRequestsKey: widget.tutorialRequestsKey,
            tutorialTabsKey: widget.tutorialTabsKey,
            tutorialApprovalFiltersKey: widget.tutorialApprovalFiltersKey,
          );
    return child;
  }
}
