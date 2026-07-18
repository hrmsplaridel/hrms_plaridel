import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeLocatorTutorial {
  EmployeeLocatorTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required GlobalKey headerKey,
    required GlobalKey requestsKey,
  }) => [
    EmployeeTutorialTarget(
      key: headerKey,
      title: 'Locator Requests',
      body:
          'Select File Request to enter the destination, purpose, schedule, and required trip details.',
    ),
    EmployeeTutorialTarget(
      key: requestsKey,
      title: 'Find and track requests',
      body:
          'Use the status, date, and search filters, then open a request to review its approval status and remarks.',
    ),
  ];
}
