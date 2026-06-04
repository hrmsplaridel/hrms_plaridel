import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';

class EmployeeLocatorSlipMobilePage extends StatefulWidget {
  const EmployeeLocatorSlipMobilePage({super.key});

  @override
  State<EmployeeLocatorSlipMobilePage> createState() =>
      EmployeeLocatorSlipMobilePageState();
}

class EmployeeLocatorSlipMobilePageState
    extends State<EmployeeLocatorSlipMobilePage> {
  final GlobalKey<EmployeeLocatorSlipContentState> _contentKey =
      GlobalKey<EmployeeLocatorSlipContentState>();

  Future<void> openCreateForm() async {
    await _contentKey.currentState?.openCreateForm();
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeLocatorSlipContent(key: _contentKey);
  }
}
