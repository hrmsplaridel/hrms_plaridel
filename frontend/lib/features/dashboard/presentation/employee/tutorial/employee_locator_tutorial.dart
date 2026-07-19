import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeLocatorTutorial {
  EmployeeLocatorTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required bool isDepartmentHead,
    required GlobalKey headerKey,
    required GlobalKey requestsKey,
  }) => [
    EmployeeTutorialTarget(
      key: headerKey,
      title: isDepartmentHead ? 'Locator Approvals' : 'Locator Requests',
      body: isDepartmentHead
          ? 'You are viewing Locator as a department head. Review employee locator, pass-slip, and work-from-home requests assigned to you.'
          : 'Select File Request to enter the destination, purpose, schedule, and required trip details.',
    ),
    EmployeeTutorialTarget(
      key: requestsKey,
      title: isDepartmentHead
          ? 'Review requests and approval history'
          : 'Find and track requests',
      body: isDepartmentHead
          ? 'Use the filters to find pending or completed requests, open their details, and record or review the appropriate approval action.'
          : 'Use the status, date, and search filters, then open a request to review its approval status and remarks.',
    ),
  ];
}
