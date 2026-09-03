import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeAttendanceTutorial {
  EmployeeAttendanceTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required GlobalKey headerKey,
    required GlobalKey filtersKey,
    required GlobalKey recordsKey,
  }) => [
    EmployeeTutorialTarget(
      key: headerKey,
      title: 'My Attendance',
      body: 'This page contains your official time-in and time-out records.',
    ),
    EmployeeTutorialTarget(
      key: filtersKey,
      title: 'Choose a period',
      body:
          'Filter the records by month, year, or day. Use refresh to return to the current period.',
    ),
    EmployeeTutorialTarget(
      key: recordsKey,
      title: 'Review your records',
      body:
          'Check each date’s time entries, late and undertime minutes, remarks, and attendance source.',
    ),
  ];
}
