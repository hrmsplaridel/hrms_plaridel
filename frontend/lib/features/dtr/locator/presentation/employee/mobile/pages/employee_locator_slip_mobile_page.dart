import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_slip_form_initial_values.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';

class EmployeeLocatorSlipMobilePage extends StatefulWidget {
  const EmployeeLocatorSlipMobilePage({
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
  State<EmployeeLocatorSlipMobilePage> createState() =>
      EmployeeLocatorSlipMobilePageState();
}

class EmployeeLocatorSlipMobilePageState
    extends State<EmployeeLocatorSlipMobilePage> {
  final GlobalKey<EmployeeLocatorSlipContentState> _contentKey =
      GlobalKey<EmployeeLocatorSlipContentState>();

  void showSection({required bool approvals}) =>
      _contentKey.currentState?.showSection(approvals: approvals);

  Future<void> openCreateForm({
    LocatorSlipFormInitialValues? initialValues,
  }) async {
    await _contentKey.currentState?.openCreateForm(
      initialValues: initialValues,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeLocatorSlipContent(
      key: _contentKey,
      tutorialHeaderKey: widget.tutorialHeaderKey,
      tutorialRequestsKey: widget.tutorialRequestsKey,
      tutorialTabsKey: widget.tutorialTabsKey,
      tutorialApprovalFiltersKey: widget.tutorialApprovalFiltersKey,
    );
  }
}
