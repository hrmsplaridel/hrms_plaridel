import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeTrainingReportsTutorial {
  EmployeeTrainingReportsTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required GlobalKey headerKey,
    required GlobalKey formKey,
    required GlobalKey historyKey,
  }) => [
    EmployeeTutorialTarget(
      key: headerKey,
      title: 'Daily Training Reports',
      body:
          'Submit the activities and accomplishments completed during each training day.',
    ),
    EmployeeTutorialTarget(
      key: formKey,
      title: 'Prepare a new report',
      body:
          'Enter the report details, add supporting evidence when required, and review everything before submitting.',
    ),
    EmployeeTutorialTarget(
      key: historyKey,
      title: 'Review previous reports',
      body:
          'Filter saved reports by date and open an entry to see the complete information you submitted.',
    ),
  ];
}
