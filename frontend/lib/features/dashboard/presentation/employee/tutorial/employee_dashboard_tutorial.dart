import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeDashboardTutorial {
  EmployeeDashboardTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required GlobalKey welcomeKey,
    required GlobalKey attendanceKey,
    required GlobalKey documentsKey,
  }) => [
    EmployeeTutorialTarget(
      key: welcomeKey,
      title: 'This is your dashboard',
      body:
          'Start here for a quick view of your employee account and today’s HR information.',
    ),
    EmployeeTutorialTarget(
      key: attendanceKey,
      title: 'Your attendance overview',
      body:
          'This area summarizes today’s record, monthly attendance, leave balance, and upcoming leave.',
    ),
    EmployeeTutorialTarget(
      key: documentsKey,
      title: 'Track your documents',
      body:
          'DocuTracker shows your documents and routing status. Open a record to follow its progress.',
    ),
  ];
}
