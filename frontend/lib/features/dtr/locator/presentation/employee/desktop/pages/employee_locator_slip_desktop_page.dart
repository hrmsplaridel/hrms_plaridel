import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_slip_form_initial_values.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';

class EmployeeLocatorSlipScreen extends StatefulWidget {
  const EmployeeLocatorSlipScreen({super.key});

  @override
  State<EmployeeLocatorSlipScreen> createState() =>
      EmployeeLocatorSlipScreenState();
}

class EmployeeLocatorSlipScreenState extends State<EmployeeLocatorSlipScreen> {
  final GlobalKey<EmployeeLocatorSlipContentState> _contentKey =
      GlobalKey<EmployeeLocatorSlipContentState>();

  Future<void> openCreateForm({
    LocatorSlipFormInitialValues? initialValues,
  }) async {
    await _contentKey.currentState?.openCreateForm(
      initialValues: initialValues,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeLocatorSlipContent(key: _contentKey);
  }
}
