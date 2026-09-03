import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeProfileSettingsTutorial {
  EmployeeProfileSettingsTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required GlobalKey heroKey,
    required GlobalKey tabsKey,
    required GlobalKey contentKey,
  }) => [
    EmployeeTutorialTarget(
      key: heroKey,
      title: 'Your employee profile',
      body:
          'Review your account identity, change your profile photo, or use Back to return to the dashboard.',
    ),
    EmployeeTutorialTarget(
      key: tabsKey,
      title: 'Profile, security, and preferences',
      body:
          'Use these tabs to switch between personal information, password security, and application settings.',
    ),
    EmployeeTutorialTarget(
      key: contentKey,
      title: 'Manage the selected section',
      body:
          'Review and update the available fields here. Save changes before switching to another section.',
    ),
  ];
}
