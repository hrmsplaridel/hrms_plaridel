import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeLeaveTutorial {
  EmployeeLeaveTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required bool showHeader,
    required bool isDepartmentHead,
    required GlobalKey headerKey,
    required GlobalKey contentKey,
  }) => [
    if (showHeader)
      EmployeeTutorialTarget(
        key: headerKey,
        title: isDepartmentHead ? 'Leave Approvals' : 'My Leave',
        body: isDepartmentHead
            ? 'You are viewing this module as a department head. Review employee leave applications assigned to you.'
            : 'Use this module to review balances, file leave, and follow approval progress.',
      ),
    EmployeeTutorialTarget(
      key: contentKey,
      title: isDepartmentHead
          ? 'Review requests and record decisions'
          : 'Balances and requests',
      body: isDepartmentHead
          ? 'Use the filters to find requests, open an application to inspect its details, then approve, return, reject, or forward it as permitted.'
          : 'Check your available credits and request history here. Select File Leave to create, save, or submit a request.',
    ),
  ];
}
