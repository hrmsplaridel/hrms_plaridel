import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeDocuTrackerTutorial {
  EmployeeDocuTrackerTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required GlobalKey headerKey,
    required GlobalKey navigationKey,
    required GlobalKey contentKey,
  }) => [
    EmployeeTutorialTarget(
      key: headerKey,
      title: 'DocuTracker',
      body:
          'Create, receive, and follow documents as they move through the configured routing workflow.',
    ),
    EmployeeTutorialTarget(
      key: navigationKey,
      title: 'Choose a document view',
      body:
          'Switch between the dashboard summary and your documents to find the information you need.',
    ),
    EmployeeTutorialTarget(
      key: contentKey,
      title: 'Track routing progress',
      body:
          'Open a document to review its current office, status, assignees, deadlines, and complete audit history.',
    ),
  ];
}
